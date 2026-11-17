// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import SQLite3
import ZIPFoundation

/// Lossless Voice Memos & call-recording audio export (A16).
///
/// Mechanism follows Erosion-CN's `VoiceMemosAIView` (Kianuni,
/// GPL-3.0), reimplemented for LilaShift's access helper: the Voice
/// Memos app container (`com.apple.VoiceMemos`, via the LaunchServices
/// cache) and its AppGroup (`group.com.apple.VoiceMemos.shared`) are
/// discovered read-only, `CloudRecordings.db` is parsed through an
/// APFS clonefile snapshot (the live database is never locked), and
/// the `.m4a` / `.qta` / `.wav` / `.caf` audio files are listed with
/// their custom titles and durations. Export copies the original
/// audio bytes unchanged (single file share, or a batch `.zip`);
/// nothing is ever written into the Voice Memos container.
///
/// Privacy boundary: this reads the user's OWN voice memos — the
/// recordings they made themselves. It does not touch other apps'
/// private data, and it never modifies or deletes a recording.
enum VoiceMemoExport {
    struct Recording: Identifiable, Equatable, Codable {
        let id: String
        let fileURL: URL
        let displayTitle: String
        let originalFileName: String
        let durationSeconds: Double?
        let createdAt: Date
        let fileSizeBytes: Int64
    }

    struct RecordingMeta: Equatable {
        let title: String
        let duration: Double?
    }

    static let voiceMemosBundleID = "com.apple.VoiceMemos"
    static let voiceMemosGroupID = "group.com.apple.VoiceMemos.shared"
    static let mediaRecordingsPath = "/private/var/mobile/Media/Recordings"
    static let audioExtensions: Set<String> = ["m4a", "qta", "wav", "caf"]

    /// Candidate roots for recordings: the Voice Memos app container,
    /// its AppGroup, and the directly readable Media recordings
    /// directory (never granted through worse_query when it is not a
    /// container). Empty on the simulator, where no container exists.
    static func discoverRoots() -> [URL] {
        var roots: [URL] = []
        #if os(iOS) && !targetEnvironment(simulator)
        if let container = GXCustomizationAccess.applicationContainer(for: voiceMemosBundleID, hint: nil),
           !container.isEmpty {
            let url = URL(fileURLWithPath: container, isDirectory: true)
            _ = ContainerAccess.grantAccess(path: url.path, requireWrite: false)
            roots.append(url)
        }
        for group in AppGroupDiscovery.groups(for: voiceMemosBundleID) {
            _ = ContainerAccess.grantAccess(path: group.path, requireWrite: false)
            roots.append(group.url)
        }
        #endif
        let media = URL(fileURLWithPath: mediaRecordingsPath, isDirectory: true)
        if FileManager.default.isReadableFile(atPath: media.path) {
            roots.append(media)
        }
        return roots
    }

    /// Lists recordings under the given roots. Pure over the file
    /// system (no container discovery), so tests can pass temp dirs.
    static func recordings(in roots: [URL]) -> [Recording] {
        let fm = FileManager.default
        var metadataByFileName: [String: RecordingMeta] = [:]
        var audioFiles: [URL] = []
        var seenCanonicalPaths = Set<String>()
        for root in roots {
            for dir in candidateDirectories(under: root) {
                _ = ContainerAccess.grantAccess(path: dir.path, requireWrite: false)
                guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
                for name in names {
                    let fullURL = dir.appendingPathComponent(name)
                    let lower = name.lowercased()
                    if lower.hasSuffix(".db") && (lower.contains("recording") || lower.contains("voicememo")) {
                        for (key, value) in parseCloudRecordingsDB(at: fullURL.path) where metadataByFileName[key] == nil {
                            metadataByFileName[key] = value
                        }
                    } else if audioExtensions.contains(fullURL.pathExtension.lowercased()) {
                        let canonical = fullURL.standardizedFileURL.path
                        if seenCanonicalPaths.insert(canonical).inserted {
                            audioFiles.append(fullURL)
                        }
                    }
                }
            }
        }
        var items: [Recording] = []
        for url in audioFiles {
            var st = stat()
            guard stat(url.path, &st) == 0, st.st_size > 0 else { continue }
            let fileName = url.lastPathComponent
            let baseName = url.deletingPathExtension().lastPathComponent
            let meta = metadataByFileName[fileName] ?? metadataByFileName[baseName]
            let mtime = Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
            let title = (meta?.title.isEmpty == false) ? meta!.title : baseName
            items.append(Recording(id: url.path, fileURL: url, displayTitle: title,
                                   originalFileName: fileName, durationSeconds: meta?.duration,
                                   createdAt: mtime, fileSizeBytes: Int64(st.st_size)))
        }
        items.sort { $0.createdAt > $1.createdAt }
        return items
    }

    /// Subdirectories a Voice Memos container keeps recordings in.
    static func candidateDirectories(under root: URL) -> [URL] {
        [root,
         root.appendingPathComponent("Recordings"),
         root.appendingPathComponent("Documents"),
         root.appendingPathComponent("Documents/Recordings"),
         root.appendingPathComponent("Library/Application Support/com.apple.voicememos/Recordings")]
    }

    /// Parses a `CloudRecordings.db` through an APFS clonefile
    /// snapshot (read-only). Returns filename/stem → title + duration.
    /// Returns an empty map when the database or its recording table
    /// is absent — never throws for a missing database.
    static func parseCloudRecordingsDB(at dbPath: String) -> [String: RecordingMeta] {
        guard let map = try? SQLiteSnapshotHelper.withClonedDatabase(at: dbPath, body: { db -> [String: RecordingMeta] in
            let tables = SQLiteSnapshotHelper.allTables(in: db)
            guard let targetTable = tables.first(where: { $0.uppercased().contains("CLOUDRECORDING") || $0.uppercased() == "ZRECORDING" }) else {
                return [:]
            }
            let cols = SQLiteSnapshotHelper.columnNames(in: targetTable, db: db)
            let pathCol = cols.contains("ZPATH") ? "ZPATH" : (cols.contains("ZFILENAME") ? "ZFILENAME" : nil)
            guard let validPathCol = pathCol else { return [:] }
            let sortLabelExpr = cols.contains("ZCUSTOMLABELFORSORTING") ? "ZCUSTOMLABELFORSORTING" : "''"
            let customLabelExpr = cols.contains("ZCUSTOMLABEL") ? "ZCUSTOMLABEL" : "''"
            let durCol = cols.contains("ZDURATION") ? "ZDURATION" : "NULL"
            let sql = "SELECT \(validPathCol), \(sortLabelExpr), \(customLabelExpr), \(durCol) FROM \"\(targetTable)\" WHERE \(validPathCol) IS NOT NULL;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
                  let validStmt = stmt else {
                return [:]
            }
            defer { sqlite3_finalize(validStmt) }
            var out: [String: RecordingMeta] = [:]
            while sqlite3_step(validStmt) == SQLITE_ROW {
                guard let rawPath = SQLiteSnapshotHelper.stringCol(validStmt, 0), !rawPath.isEmpty else { continue }
                let sortLabel = SQLiteSnapshotHelper.stringCol(validStmt, 1) ?? ""
                let customLabel = SQLiteSnapshotHelper.stringCol(validStmt, 2) ?? ""
                let label = normalizeRecordingLabel(sortingLabel: sortLabel, customLabel: customLabel)
                let duration = SQLiteSnapshotHelper.doubleCol(validStmt, 3)
                let lastComp = (rawPath as NSString).lastPathComponent
                let stem = (lastComp as NSString).deletingPathExtension
                let meta = RecordingMeta(title: label, duration: duration)
                out[lastComp] = meta
                out[stem] = meta
            }
            return out
        }) else {
            return [:]
        }
        return map
    }

    /// Picks the display label: a custom label wins over the
    /// timestamp-style sorting label; a bare timestamp becomes
    /// "Recording <date>".
    static func normalizeRecordingLabel(sortingLabel: String, customLabel: String) -> String {
        let candidates = [sortingLabel, customLabel]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for candidate in candidates {
            if iso.date(from: candidate) == nil && isoFrac.date(from: candidate) == nil {
                return candidate
            }
        }
        if let first = candidates.first,
           let parsed = iso.date(from: first) ?? isoFrac.date(from: first) {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd HH:mm"
            return "Recording \(df.string(from: parsed))"
        }
        return candidates.first ?? ""
    }

    /// Replaces filename-unsafe characters. Never returns empty.
    static func sanitizeFileName(_ raw: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = raw.components(separatedBy: invalid).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Recording" : cleaned
    }

    static func formatDuration(_ seconds: Double) -> String {
        let total = max(Int(seconds.rounded()), 0)
        let hrs = total / 3600
        let mins = (total % 3600) / 60
        let secs = total % 60
        if hrs > 0 {
            return String(format: "%d:%02d:%02d", hrs, mins, secs)
        }
        return String(format: "%02d:%02d", mins, secs)
    }

    /// Copies the recordings into a staging directory and zips them.
    /// Returns the `.zip` URL (in the temporary directory); the
    /// caller shares it and removes it afterwards. Throws when no
    /// recording could be read.
    static func zipRecordings(_ recordings: [Recording]) throws -> URL {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("VoiceMemosExport_\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        var usedNames = Set<String>()
        var copied = 0
        for rec in recordings {
            _ = ContainerAccess.grantAccess(path: rec.fileURL.deletingLastPathComponent().path, requireWrite: false)
            let ext = rec.fileURL.pathExtension.isEmpty ? "m4a" : rec.fileURL.pathExtension
            let base = sanitizeFileName(rec.displayTitle)
            var candidate = "\(base).\(ext)"
            var suffix = 2
            while usedNames.contains(candidate.lowercased()) {
                candidate = "\(base)_\(suffix).\(ext)"
                suffix += 1
            }
            usedNames.insert(candidate.lowercased())
            if (try? fm.copyItem(at: rec.fileURL, to: staging.appendingPathComponent(candidate))) != nil {
                copied += 1
            }
        }
        guard copied > 0 else {
            throw CustomizationFailure("Could not read any recording audio file.")
        }
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd_HHmmss"
        let zipURL = fm.temporaryDirectory.appendingPathComponent("LilaShift_VoiceMemos_\(stamp.string(from: Date())).zip")
        try? fm.removeItem(at: zipURL)
        try fm.zipItem(at: staging, to: zipURL, shouldKeepParent: false)
        return zipURL
    }
}
