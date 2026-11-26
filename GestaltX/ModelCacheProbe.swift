// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// On-device AI / offline translation & speech model cache readiness
/// probe (A20, read-only).
///
/// Mechanism follows Erosion-CN's `VoiceMemosAIView.probeAIModelCaches`
/// (Kianuni, GPL-3.0), reimplemented for LilaShift's access helper:
/// the app containers for offline translation, Voice Memos
/// transcription and Shortcuts automation are located through the
/// LaunchServices cache, and the translation / media-analysis
/// SystemGroup paths are probed directly. Each target reports how
/// many files it holds and their total size (depth-limited), or that
/// it is sandboxed/unavailable — never a guessed number.
///
/// Honesty limit (same as the source): the Apple Intelligence core
/// model weights live in the MobileAsset read-only volume managed by
/// protected daemons. This probe counts only the readable system
/// translation, voice-memo transcription and visual-analysis
/// container caches — it does not, and cannot, report the core
/// model weights.
enum ModelCacheProbe {
    struct Item: Identifiable, Equatable, Codable {
        let id: String
        let title: String
        let identifier: String
        let accessible: Bool
        let fileCount: Int
        let totalBytes: Int64
        let statusNote: String
    }

    static let maxDepth = 4

    /// App containers probed for offline AI / translation caches.
    static let appTargets: [(title: String, bundleID: String)] = [
        ("System Translation Offline Language Packs", "com.apple.Translate"),
        ("Voice Memos & Transcription Cache", "com.apple.VoiceMemos"),
        ("Shortcuts & Intelligence Automation", "com.apple.shortcuts"),
    ]

    /// SystemGroup / MobileAsset read-only probes.
    static let systemTargets: [(title: String, id: String, path: String)] = [
        ("Offline Translation Engine Shared Group", "systemgroup.com.apple.translationd",
         "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.translationd"),
        ("Visual Image Intelligence Analysis Group", "systemgroup.com.apple.mediaanalysisd",
         "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mediaanalysisd"),
    ]

    /// Probes every target. Container lookup is device-only; on the
    /// simulator every app target reports "container not found".
    static func probe() -> [Item] {
        var results: [Item] = []
        for target in appTargets {
            results.append(probeAppContainer(title: target.title, bundleID: target.bundleID))
        }
        for sys in systemTargets {
            if let item = probeSystemPath(title: sys.title, id: sys.id, path: sys.path) {
                results.append(item)
            }
        }
        return results
    }

    /// Probes one app container by bundle ID. Testable over a path
    /// through `probePath(title:id:path:)`.
    static func probeAppContainer(title: String, bundleID: String) -> Item {
        #if os(iOS) && !targetEnvironment(simulator)
        if let path = GXCustomizationAccess.applicationContainer(for: bundleID, hint: nil), !path.isEmpty {
            return probePath(title: title, id: bundleID, path: path,
                             notFoundNote: "Container not found (app may not be installed or never launched)",
                             deniedNote: "Sandbox read is restricted on this firmware")
        }
        #endif
        return Item(id: bundleID, title: title, identifier: bundleID, accessible: false,
                    fileCount: 0, totalBytes: 0,
                    statusNote: "Container not found (app may not be installed or never launched)")
    }

    /// Probes one SystemGroup path. Returns `nil` when the path does
    /// not exist at all (nothing to report).
    static func probeSystemPath(title: String, id: String, path: String) -> Item? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        return probePath(title: title, id: id, path: path,
                         notFoundNote: "Path does not exist",
                         deniedNote: "Protected by the system sandbox (daemon-readable only)")
    }

    /// Probes one readable directory path. A directory the app can
    /// already read (tests, or a container the app owns) needs no
    /// worse_query grant — the direct read is tried first, and the
    /// grant is only attempted when it fails (the AppGroupBrowser
    /// pattern). On the simulator the grant cannot succeed
    /// (`worse_query` needs iOS-only libraries), so the direct-read
    /// path is what makes this testable.
    /// Exported for tests: pass any temp directory as `path`.
    static func probePath(title: String, id: String, path: String,
                          notFoundNote: String, deniedNote: String) -> Item {
        func count() -> (Int, Int64) {
            countFilesAndSize(at: URL(fileURLWithPath: path, isDirectory: true), maxDepth: maxDepth)
        }
        func okItem(_ count: Int, _ bytes: Int64) -> Item {
            Item(id: id, title: title, identifier: id, accessible: true,
                 fileCount: count, totalBytes: bytes,
                 statusNote: "Read-only probe OK · \(count) cached files")
        }
        if (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil {
            let (count, bytes) = count()
            return okItem(count, bytes)
        }
        let grant = ContainerAccess.grantAccess(path: path, requireWrite: false)
        guard grant.granted,
              (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil else {
            return Item(id: id, title: title, identifier: id, accessible: false,
                        fileCount: 0, totalBytes: 0, statusNote: deniedNote)
        }
        defer { ContainerAccess.releaseAccess(path: path) }
        let (count, bytes) = count()
        return okItem(count, bytes)
    }

    /// Counts regular files and their total bytes under `url`, to
    /// `maxDepth` levels. Symlinks are never followed (`lstat`): a
    /// symlink to a directory is not descended into.
    static func countFilesAndSize(at url: URL, maxDepth: Int, currentDepth: Int = 0) -> (Int, Int64) {
        guard currentDepth <= maxDepth,
              let names = try? FileManager.default.contentsOfDirectory(atPath: url.path) else {
            return (0, 0)
        }
        var count = 0
        var bytes: Int64 = 0
        for name in names {
            let child = (url.path as NSString).appendingPathComponent(name)
            var st = stat()
            guard lstat(child, &st) == 0 else { continue }
            let mode = st.st_mode & S_IFMT
            if mode == S_IFREG {
                count += 1
                bytes += Int64(st.st_size)
            } else if mode == S_IFDIR {
                let sub = countFilesAndSize(at: URL(fileURLWithPath: child, isDirectory: true),
                                            maxDepth: maxDepth, currentDepth: currentDepth + 1)
                count += sub.0
                bytes += sub.1
            }
        }
        return (count, bytes)
    }

    static func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        if bytes < 1024 * 1024 * 1024 { return String(format: "%.1f MB", Double(bytes) / (1024 * 1024)) }
        return String(format: "%.2f GB", Double(bytes) / (1024 * 1024 * 1024))
    }
}
