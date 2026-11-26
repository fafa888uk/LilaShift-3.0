// SPDX-License-Identifier: GPL-3.0-only
// App archive engine (Stage 7, ADR-2-10, DATA_MODELS §4).
//
// Sandbox-compliant archives of THIS app's own data only. The
// allowlist is exactly TASKBOOK §6.2: the app's own Documents, its
// own cache, files the user picks through the document picker,
// data the user shares into the app, and authorized App Group data.
// Everything else is refused. The engine NEVER reads or writes
// another app's Documents or container, NEVER goes through the
// sandbox escape or the cross-container gate
// (ARCHITECTURE_DESIGN §2.2 forbids that edge), and NEVER presents
// itself as able to read or delete another app's private data.
// The Erosion-CN AppDataBackupView third-party backup (A10) is
// explicitly out of scope and is not implemented here in any form
// (see ~/workspace/lilashift-port-medium-a10-risk-assessment.md).
//
// Archive format: a real ZIP (ZIPFoundation 0.9.20, MIT — the same
// dependency CustomizationFiles already uses for reading) holding
// `manifest.json` plus one `files/<relativePath>` entry per file.
// The manifest carries a SHA-256 digest of its own canonical bytes
// (via BackupEngine.sha256Hex, the app's single digest), and every
// entry carries its own SHA-256; verification re-checks both, and a
// corrupt archive (manifest digest mismatch, entry digest mismatch,
// missing entry) can never be restored. Restore backs up the
// current container state first (as a pre-restore archive) and then
// writes, producing a report that lists restored, skipped and
// failed items — a failed item is reported, never hidden.
import Foundation
import ZIPFoundation

/// One of the archive allowlist roots (TASKBOOK §6.2).
enum ArchiveRootKind: String, Codable, CaseIterable, Sendable {
    case ownDocuments
    case ownCache
    case appGroup
    case sharedInbox
    case userFile

    var title: String {
        switch self {
        case .ownDocuments: return L("Own Documents")
        case .ownCache: return L("Own Cache")
        case .appGroup: return L("App Group Data")
        case .sharedInbox: return L("Shared Inbox")
        case .userFile: return L("Picked File")
        }
    }
}

/// A resolved archive source: a root URL plus the allowlist kind it
/// came from. The engine only ever touches the URL it is given, and
/// the caller is responsible for resolving it from the allowlist
/// (see `AppArchiveEngine.resolveSource(for:)` for the production
/// resolution). Tests inject temporary directories here.
struct ArchiveSource: Sendable {
    let rootURL: URL
    let kind: ArchiveRootKind
    /// The bundle ID the archived files belong to — always this
    /// app's own bundle ID, never another app's.
    let sourceApp: String
}

/// One file inside an archive (DATA_MODELS §4.2).
struct ArchiveEntry: Codable, Equatable, Sendable {
    var id: UUID
    var sourceApp: String
    /// Relative path inside the source root. Only validated paths
    /// (see `AppArchiveEngine.validateRelativePath`) may appear here.
    var relativePath: String
    var size: Int
    var sha256: String
    var capturedAt: Date
}

/// The archive manifest (DATA_MODELS §4.2), stored as
/// `manifest.json` at the root of the ZIP.
struct AppArchiveManifest: Codable, Sendable {
    var id: UUID
    /// Random install ID (`GestaltX.installationID`), never the UDID
    /// (ADR-2-06).
    var deviceID: String
    var createdAt: Date
    var root: ArchiveRootKind
    var sourceApp: String
    var entries: [ArchiveEntry]
    /// SHA-256 of the canonical manifest JSON with this field empty.
    var manifestSha256: String
    var formatVersion: Int
}

/// An archive on disk, as listed by `scanArchives`.
struct AppArchiveInfo: Sendable {
    var manifest: AppArchiveManifest
    var fileURL: URL
    var byteCount: Int
}

/// What `scanArchives` found: valid archives plus the file names
/// whose manifest could not be read (shown as corrupt, never as
/// valid).
struct ArchiveScan: Sendable {
    var valid: [AppArchiveInfo]
    var corrupt: [String]
}

/// The result of creating an archive.
struct ArchiveCreationReport: Sendable {
    var archiveID: UUID
    var fileURL: URL
    var entries: [ArchiveEntry]
    /// Symlinks are never archived; their paths are listed here so
    /// the omission is visible, not silent.
    var skippedSymlinks: [String]
    var totalBytes: Int
}

/// One file that could not be restored, with the reason.
struct ArchiveRestoreFailure: Sendable {
    var path: String
    var reason: String
}

/// The result of restoring an archive. A restore is never reported
/// as a bare success: restored, skipped and failed items are all
/// listed, and the pre-restore archive is always named.
struct ArchiveRestoreReport: Sendable {
    var archiveID: UUID
    var restored: [String]
    var skipped: [String]
    var failed: [ArchiveRestoreFailure]
    var preRestoreArchiveID: UUID
    var restoredAt: Date
}

enum AppArchiveEngine {
    static let currentFormatVersion = 1
    /// Same caps as CustomizationFiles: one implementation of the
    /// size limits, reused here rather than re-declared.
    static let maximumEntries = 4000

    /// The directory archives live in, under the app's own
    /// Application Support.
    static func archivesDirectory() -> URL {
        AppDirectories.appArchivesStorage
    }

    /// The install ID (`GestaltX.installationID`), or "local" when
    /// it was never set. Never the UDID (ADR-2-06).
    static func installationID() -> String {
        UserDefaults.standard.string(forKey: "GestaltX.installationID") ?? "local"
    }

    /// Resolves a production archive source from the allowlist kind.
    /// Returns `nil` when the root cannot be resolved (e.g. no App
    /// Group container) — the caller reports that, it is not faked.
    static func resolveSource(for kind: ArchiveRootKind, pickedFile: URL? = nil) -> ArchiveSource? {
        let fm = FileManager.default
        let bundleID = Bundle.main.bundleIdentifier ?? "com.huami.gestultx"
        switch kind {
        case .ownDocuments:
            let url = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            return ArchiveSource(rootURL: url, kind: kind, sourceApp: bundleID)
        case .ownCache:
            let url = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            return ArchiveSource(rootURL: url, kind: kind, sourceApp: bundleID)
        case .appGroup:
            guard let url = fm.containerURL(forSecurityApplicationGroupIdentifier: GestaltKeys.group) else { return nil }
            return ArchiveSource(rootURL: url, kind: kind, sourceApp: bundleID)
        case .sharedInbox:
            guard let container = fm.containerURL(forSecurityApplicationGroupIdentifier: GestaltKeys.group) else { return nil }
            let url = container.appendingPathComponent("GestaltX/ShareInbox", isDirectory: true)
            return ArchiveSource(rootURL: url, kind: kind, sourceApp: bundleID)
        case .userFile:
            guard let pickedFile else { return nil }
            return ArchiveSource(rootURL: pickedFile, kind: kind, sourceApp: bundleID)
        }
    }

    /// Validates a relative path. Delegates to
    /// `CustomizationFiles.relative` — the one path validator in the
    /// app — which rejects empty paths, absolute paths, ".." and "."
    /// components, empty components, backslashes and NUL.
    static func validateRelativePath(_ path: String) throws -> String {
        try CustomizationFiles.relative(path)
    }

    /// Lists the archives in a directory: valid manifests plus the
    /// names of files whose manifest could not be read.
    static func scanArchives(in directory: URL) -> ArchiveScan {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: directory.path)) ?? []
        var valid: [AppArchiveInfo] = []
        var corrupt: [String] = []
        for name in names.sorted() where name.hasSuffix(".zip") {
            let url = directory.appendingPathComponent(name)
            do {
                let manifest = try readManifest(from: url)
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                valid.append(AppArchiveInfo(manifest: manifest, fileURL: url, byteCount: size))
            } catch {
                corrupt.append(name)
            }
        }
        valid.sort { $0.manifest.createdAt > $1.manifest.createdAt }
        return ArchiveScan(valid: valid, corrupt: corrupt)
    }

    /// Creates an archive ZIP of a source root. The source may be a
    /// directory (all regular files under it, recursively) or a
    /// single file (the `.userFile` kind). Symlinks are skipped and
    /// listed in the report. Throws on the first unreadable file —
    /// a partial archive is never written.
    static func createArchive(from source: ArchiveSource,
                              deviceID: String = installationID(),
                              to directory: URL? = nil,
                              progress: ((Double) -> Void)? = nil) async throws -> ArchiveCreationReport {
        let archivesDir = directory ?? archivesDirectory()
        try FileManager.default.createDirectory(at: archivesDir, withIntermediateDirectories: true)
        let manifestID = UUID()
        let createdAt = Date()
        let collected = try await collectEntries(from: source, capturedAt: createdAt, progress: progress)
        let entries = collected.entries
        var manifest = AppArchiveManifest(
            id: manifestID, deviceID: deviceID, createdAt: createdAt,
            root: source.kind, sourceApp: source.sourceApp, entries: entries,
            manifestSha256: "", formatVersion: currentFormatVersion)
        manifest.manifestSha256 = digest(of: manifest)
        let manifestData = try canonicalManifestData(for: manifest)
        let fileName = "archive-\(manifestID.uuidString).zip"
        let archiveFileURL = archivesDir.appendingPathComponent(fileName)
        do {
            let archive = try Archive(url: archiveFileURL, accessMode: .create)
            // ZIPFoundation 0.9.20 has no addEntry(with:data:) overload:
            // in-memory data goes in through the provider overload
            // (README "Closure based Reading and Writing"), which is
            // called with (position, size) until uncompressedSize
            // bytes are provided.
            try archive.addEntry(with: "manifest.json", type: .file,
                                 uncompressedSize: Int64(manifestData.count),
                                 compressionMethod: .deflate) { position, size in
                let start = Int(position)
                let end = min(start + size, manifestData.count)
                guard start < end else { return Data() }
                return manifestData.subdata(in: start..<end)
            }
            for entry in entries {
                try Task.checkCancellation()
                let entryFileURL = try fileURL(for: entry, in: source)
                try archive.addEntry(with: "files/" + entry.relativePath, fileURL: entryFileURL,
                                     compressionMethod: .deflate)
            }
        } catch {
            try? FileManager.default.removeItem(at: archiveFileURL)
            throw error
        }
        return ArchiveCreationReport(
            archiveID: manifestID, fileURL: archiveFileURL, entries: entries,
            skippedSymlinks: collected.skippedSymlinks,
            totalBytes: entries.reduce(0) { $0 + $1.size })
    }

    /// Reads and verifies a manifest: decodes it, rejects unknown
    /// format versions, and recomputes its SHA-256 digest. Does not
    /// verify entry payloads — use `verifyArchive` for that.
    static func readManifest(from archiveURL: URL) throws -> AppArchiveManifest {
        let data = try extractEntry(named: "manifest.json", from: archiveURL)
        let manifest = try migrateManifest(data)
        try verifyManifestDigest(manifest)
        return manifest
    }

    /// Recomputes a manifest's SHA-256 digest and throws on a
    /// mismatch. A manifest whose digest does not match its bytes
    /// was altered after creation.
    static func verifyManifestDigest(_ manifest: AppArchiveManifest) throws {
        guard manifest.manifestSha256 == digest(of: manifest) else {
            throw GestaltFailure("The archive manifest does not match its contents.")
        }
    }

    /// Checks one entry against its bytes: size and SHA-256 must
    /// both match the manifest.
    static func verifyEntry(_ entry: ArchiveEntry, data: Data) throws {
        guard data.count == entry.size, BackupEngine.sha256Hex(of: data) == entry.sha256 else {
            throw GestaltFailure("The archive entry does not match its recorded digest.")
        }
    }

    /// Fully verifies an archive: manifest digest plus every entry's
    /// size and SHA-256. Any mismatch throws; a failed verification
    /// must never be followed by a restore.
    static func verifyArchive(at archiveURL: URL) throws -> AppArchiveManifest {
        let manifest = try readManifest(from: archiveURL)
        var total = 0
        for entry in manifest.entries {
            let path = try validateRelativePath(entry.relativePath)
            let data = try extractEntry(named: "files/" + path, from: archiveURL)
            total += data.count
            guard total <= CustomizationFiles.maximumTotal else {
                throw GestaltFailure("The archive is invalid or exceeds the size limit.")
            }
            try verifyEntry(entry, data: data)
        }
        return manifest
    }

    /// Restores an archive into its source root: verifies the
    /// manifest and every entry first, backs up the current root
    /// state as a pre-restore archive, then writes. Files that fail
    /// to write are recorded in the report and skipped; the restore
    /// never claims a file it did not write.
    static func restoreArchive(at archiveURL: URL,
                               to source: ArchiveSource,
                               deviceID: String = installationID(),
                               archivesDirectory: URL? = nil,
                               progress: ((Double) -> Void)? = nil) async throws -> ArchiveRestoreReport {
        let manifest = try verifyArchive(at: archiveURL)
        let archivesDir = archivesDirectory ?? Self.archivesDirectory()
        // Back up the current state first (TASKBOOK §4.3 rule, also
        // applied to archives): a failed restore can go back to it.
        // A picked file that is gone has nothing to back up — that
        // is the case restore exists for — so an empty pre-restore
        // archive is recorded instead of failing the restore.
        let preRestore: ArchiveCreationReport
        if source.kind == .userFile,
           !FileManager.default.fileExists(atPath: source.rootURL.path) {
            let emptyDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("GX-EmptyRestore-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: emptyDir) }
            preRestore = try await createArchive(
                from: ArchiveSource(rootURL: emptyDir, kind: source.kind, sourceApp: source.sourceApp),
                deviceID: deviceID, to: archivesDir)
        } else {
            preRestore = try await createArchive(
                from: source, deviceID: deviceID, to: archivesDir)
        }
        // A picked file restores onto itself; a directory root
        // restores into the directory. Either way the write root is
        // a directory that must exist before `checked` runs.
        let restoreRoot = source.kind == .userFile
            ? source.rootURL.deletingLastPathComponent() : source.rootURL
        try FileManager.default.createDirectory(at: restoreRoot, withIntermediateDirectories: true)
        var restored: [String] = []
        var skipped: [String] = []
        var failed: [ArchiveRestoreFailure] = []
        let total = manifest.entries.count
        for (index, entry) in manifest.entries.enumerated() {
            try Task.checkCancellation()
            progress?(total == 0 ? 1 : Double(index) / Double(total))
            do {
                let path = try validateRelativePath(entry.relativePath)
                let data = try extractEntry(named: "files/" + path, from: archiveURL)
                try verifyEntry(entry, data: data)
                let target = try CustomizationFiles.checked(path, in: restoreRoot, missing: true)
                // Already identical on disk: skip the write and say
                // so, instead of rewriting and claiming a restore.
                if let existing = try? CustomizationFiles.read(target),
                   existing == data {
                    skipped.append(path)
                    continue
                }
                try FileManager.default.createDirectory(
                    at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: target, options: .atomic)
                // Read back and verify what was written.
                let written = try CustomizationFiles.read(target)
                guard written == data else {
                    throw GestaltFailure("The restored file could not be verified.")
                }
                restored.append(path)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failed.append(ArchiveRestoreFailure(path: entry.relativePath, reason: error.localizedDescription))
            }
        }
        progress?(1)
        return ArchiveRestoreReport(
            archiveID: manifest.id, restored: restored, skipped: skipped,
            failed: failed, preRestoreArchiveID: preRestore.archiveID, restoredAt: Date())
    }

    /// Deletes an archive file. Refuses anything that is not a
    /// `.zip` inside the archives directory, so a wrong URL can
    /// never delete user data.
    static func deleteArchive(at url: URL, in directory: URL? = nil) throws {
        let archivesDir = directory ?? archivesDirectory()
        guard url.pathExtension == "zip",
              url.deletingLastPathComponent().standardizedFileURL == archivesDir.standardizedFileURL else {
            throw GestaltFailure("Only archive files inside the archives directory can be deleted.")
        }
        try FileManager.default.removeItem(at: url)
    }

    /// Decodes a manifest and enforces the format version. This is
    /// the migration entry point: today only v1 exists, and any
    /// other version is honestly rejected instead of silently
    /// upgraded. When a v2 format ships, add its migration here.
    static func migrateManifest(_ data: Data) throws -> AppArchiveManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(AppArchiveManifest.self, from: data)
        guard manifest.formatVersion == currentFormatVersion else {
            throw GestaltFailure("This archive version is not supported.")
        }
        return manifest
    }

    /// Canonical manifest JSON (sorted keys, ISO-8601 dates) — the
    /// bytes the manifest digest is computed over, and the bytes
    /// stored in the ZIP.
    static func canonicalManifestData(for manifest: AppArchiveManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(manifest)
    }

    // MARK: - Private helpers

    /// The manifest digest: SHA-256 of the canonical manifest JSON
    /// with the digest field itself empty.
    private static func digest(of manifest: AppArchiveManifest) -> String {
        var unsigned = manifest
        unsigned.manifestSha256 = ""
        guard let data = try? canonicalManifestData(for: unsigned) else { return "" }
        return BackupEngine.sha256Hex(of: data)
    }

    private struct CollectedEntries {
        var entries: [ArchiveEntry]
        var skippedSymlinks: [String]
    }

    /// Enumerates a source root into entries. A single-file source
    /// yields one entry named by its last path component.
    private static func collectEntries(from source: ArchiveSource, capturedAt: Date,
                                       progress: ((Double) -> Void)?) async throws -> CollectedEntries {
        let fm = FileManager.default
        // A missing directory root has nothing to archive (an empty
        // archive is still a valid, honest record of that). A missing
        // picked file is an error: the user chose a file that is gone.
        guard fm.fileExists(atPath: source.rootURL.path) else {
            if source.kind == .userFile {
                throw GestaltFailure("The picked file could not be archived.")
            }
            return CollectedEntries(entries: [], skippedSymlinks: [])
        }
        let isDirectory = (try? source.rootURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        var files: [(url: URL, relativePath: String)] = []
        var skippedSymlinks: [String] = []
        if isDirectory {
            guard let enumerator = fm.enumerator(
                at: source.rootURL, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
                options: [.skipsHiddenFiles], errorHandler: nil) else {
                return CollectedEntries(entries: [], skippedSymlinks: [])
            }
            for case let fileURL as URL in enumerator {
                try Task.checkCancellation()
                guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                      values.isRegularFile == true else {
                    if (try? fileURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                        skippedSymlinks.append(relativePath(of: fileURL, under: source.rootURL))
                    }
                    continue
                }
                let path = relativePath(of: fileURL, under: source.rootURL)
                // Refuse any path that passes through a symlink
                // component: `checked` walks every component, so a
                // symlinked directory inside the root can never pull
                // outside files into the archive. Such files are
                // skipped and listed, never read through the link.
                guard (try? CustomizationFiles.checked(path, in: source.rootURL)) != nil else {
                    skippedSymlinks.append(path)
                    continue
                }
                files.append((fileURL, path))
            }
        } else {
            let values = try source.rootURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw GestaltFailure("The picked file could not be archived.")
            }
            files.append((source.rootURL, source.rootURL.lastPathComponent))
        }
        guard files.count <= maximumEntries else {
            throw GestaltFailure("The archive is invalid or exceeds the size limit.")
        }
        var entries: [ArchiveEntry] = []
        var total = 0
        for (index, file) in files.enumerated() {
            try Task.checkCancellation()
            progress?(files.isEmpty ? 1 : Double(index) / Double(files.count))
            let path = try validateRelativePath(file.relativePath)
            let data = try CustomizationFiles.read(file.url)
            total += data.count
            guard total <= CustomizationFiles.maximumTotal else {
                throw GestaltFailure("The archive is invalid or exceeds the size limit.")
            }
            entries.append(ArchiveEntry(
                id: UUID(), sourceApp: source.sourceApp, relativePath: path,
                size: data.count, sha256: BackupEngine.sha256Hex(of: data), capturedAt: capturedAt))
        }
        progress?(1)
        return CollectedEntries(entries: entries, skippedSymlinks: skippedSymlinks)
    }

    private static func relativePath(of url: URL, under root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let childPath = url.standardizedFileURL.path
        guard childPath.hasPrefix(rootPath + "/") else { return url.lastPathComponent }
        return String(childPath.dropFirst(rootPath.count + 1))
    }

    private static func fileURL(for entry: ArchiveEntry, in source: ArchiveSource) throws -> URL {
        let path = try validateRelativePath(entry.relativePath)
        if source.kind == .userFile {
            return source.rootURL
        }
        return try CustomizationFiles.checked(path, in: source.rootURL)
    }

    /// Extracts one ZIP entry into memory, checking the CRC32 and
    /// the uncompressed size, and refusing symlinks, directories
    /// and duplicate paths. Bounded by `maximumFile` per entry.
    private static func extractEntry(named name: String, from archiveURL: URL) throws -> Data {
        let archive = try Archive(url: archiveURL, accessMode: .read)
        guard let entry = archive[name], entry.type == .file else {
            throw GestaltFailure("The archive is missing an entry.")
        }
        guard entry.uncompressedSize <= UInt64(CustomizationFiles.maximumFile) else {
            throw GestaltFailure("The archive is invalid or exceeds the size limit.")
        }
        var data = Data()
        data.reserveCapacity(Int(entry.uncompressedSize))
        let crc = try archive.extract(entry, bufferSize: 64 * 1024) { chunk in
            data.append(chunk)
            guard data.count <= CustomizationFiles.maximumFile else {
                throw GestaltFailure("The archive is invalid or exceeds the size limit.")
            }
        }
        guard crc == entry.checksum, UInt64(data.count) == entry.uncompressedSize else {
            throw GestaltFailure("The archive entry does not match its recorded digest.")
        }
        return data
    }
}
