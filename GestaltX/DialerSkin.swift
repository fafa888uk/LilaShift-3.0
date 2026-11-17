// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Darwin
import UIKit
import ZIPFoundation

/// Dialer (Phone app) keypad skin (A18).
///
/// Mechanism follows Erosion-CN's `KeypadManager`/`KeypadView`
/// (Kianuni, GPL-3.0), reimplemented for LilaShift's staging
/// mechanism: the Phone app's dialer buttons live as PNGs in its
/// container at `Library/Caches/TelephonyUI-10`, named
/// `<regCode>-<key>-<appearance>.png` (e.g. `other-1---mask.png`).
/// Custom images are written there; the phone shows them after the
/// appearance is toggled or the device restarts. This is NOT a
/// system-wide dialer theme — iOS has no public API for that — it
/// replaces the cached button artwork the Phone app itself reads.
///
/// Safety differences from the source, on purpose:
/// * Erosion-CN keeps originals only in memory and its reset just
///   DELETES the custom files. LilaShift instead backs every
///   overwritten file up beside itself as `name.bak` through
///   `ContainerOriginals` (the launch-image mechanism), so reset
///   restores the exact original bytes and a reinstall does not
///   orphan them. Files that were originally absent are deleted
///   on restore, not written back as empty files.
/// * Writes are atomic (temp file + `renameat`, the launch-image
///   pattern), verified by readback, and rolled back on partial
///   failure; theme ZIPs are rejected when any entry escapes the
///   extraction directory.
/// * Empty or invalid PNG data is never written.
enum DialerSkin {
    /// The Phone app's container bundle ID.
    static let mobilePhoneBundleID = "com.apple.mobilephone"
    /// The keypad artwork directory inside the Phone container.
    static let telephonyUIDirectory = "Library/Caches/TelephonyUI-10"
    /// Maximum keypad image size (keypad PNGs are small).
    static let maximumFile = 5 * 1024 * 1024

    enum KeypadID: String, CaseIterable {
        case one, two, three, four, five, six, seven, eight, nine, star, zero, pound

        var keyFragment: String {
            switch self {
            case .one: return "-1-"
            case .two: return "-2-A B C"
            case .three: return "-3-D E F"
            case .four: return "-4-G H I"
            case .five: return "-5-J K L"
            case .six: return "-6-M N O"
            case .seven: return "-7-P Q R S"
            case .eight: return "-8-T U V"
            case .nine: return "-9-W X Y Z"
            case .star: return "-*-"
            case .zero: return "-0-+"
            case .pound: return "-#-"
            }
        }

        /// The key number as it appears in a keypad filename
        /// (the second `-`-separated component).
        var keyNumber: String {
            switch self {
            case .one: return "1"
            case .two: return "2"
            case .three: return "3"
            case .four: return "4"
            case .five: return "5"
            case .six: return "6"
            case .seven: return "7"
            case .eight: return "8"
            case .nine: return "9"
            case .star: return "*"
            case .zero: return "0"
            case .pound: return "#"
            }
        }

        /// The six artwork files for this key, for a region-code
        /// prefix (light mask, dark white, highlight variants, bold
        /// variants). The prefix is detected from the existing files
        /// on the device (see `regCode`).
        func fileNames(withPrefix prefix: String) -> [String] {
            ["--mask.png", "--white.png", "-hi-mask.png", "-hi-white.png",
             "--white-bold.png", "--mask-bold.png"]
                .map { prefix + keyFragment + $0 }
        }

        /// The file the Phone app reads for this key in the given
        /// appearance: light → mask, dark → white.
        func accentedFileName(withPrefix prefix: String, dark: Bool) -> String {
            fileNames(withPrefix: prefix)[dark ? 1 : 0]
        }
    }

    /// Detects the region-code prefix from existing TelephonyUI PNG
    /// filenames: the first `-`-separated component of a PNG name,
    /// unless it is `other`. Returns `"other"` when nothing usable
    /// is found. Pure over filenames, so it is unit-testable.
    static func regCode(from fileNames: [String]) -> String {
        for name in fileNames where name.lowercased().hasSuffix(".png") {
            let split = name.split(separator: "-").map(String.init)
            if let first = split.first, !first.isEmpty, first != "other" {
                return first
            }
        }
        return "other"
    }

    /// A PNG is valid when it is longer than 64 bytes, starts with
    /// the PNG signature, and decodes as an image.
    static func isValidPNGData(_ data: Data) -> Bool {
        let pngSig: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard data.count > 64 else { return false }
        return Array(data.prefix(8)) == pngSig && UIImage(data: data) != nil
    }

    /// Resizes image data to `size` (clamped to 50–2500 px), optionally
    /// masking it into a circle. Returns the input unchanged when it
    /// is not a decodable image.
    static func resize(_ data: Data, to size: CGSize, circle: Bool = false) -> Data {
        guard let image = UIImage(data: data) else { return data }
        let width = min(max(size.width, 50), 2500)
        let height = min(max(size.height, 50), 2500)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
            .image { context in
                if circle {
                    context.cgContext.addEllipse(in: CGRect(origin: .zero, size: CGSize(width: width, height: height)))
                    context.cgContext.clip()
                }
                let fill = max(width / image.size.width, height / image.size.height)
                let drawSize = CGSize(width: image.size.width * fill, height: image.size.height * fill)
                let origin = CGPoint(x: (width - drawSize.width) / 2, y: (height - drawSize.height) / 2)
                image.draw(in: CGRect(origin: origin, size: drawSize))
            }
        return rendered.pngData() ?? data
    }

    /// The Phone container's TelephonyUI-10 directory, pinned with
    /// file descriptors like `LaunchArtworkDirectory`: a target app
    /// changing a symlink cannot redirect a write elsewhere.
    /// Backups use kind `"dialer"` so they never collide with the
    /// launch-image backups.
    final class Directory {
        struct File {
            let data: Data
            let device: UInt64
            let inode: UInt64
            let mode: mode_t
            let protection: Int32?
        }
        private let components = ["Library", "Caches", "TelephonyUI-10"]
        private let descriptors: [Int32]
        private var directory: Int32 { descriptors.last! }

        init(container: URL) throws {
            var handles: [Int32] = []
            do {
                let root = open(container.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard root >= 0 else { throw DialerSkinError.openFailed }
                handles.append(root)
                for part in components {
                    let child = openat(handles.last!, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                    guard child >= 0 else { throw DialerSkinError.openFailed }
                    handles.append(child)
                }
            } catch {
                handles.forEach { close($0) }
                throw error
            }
            descriptors = handles
        }
        deinit { descriptors.forEach { close($0) } }

        func names() throws -> [String] {
            var entries: [String] = []
            let fd = dup(directory)
            guard fd >= 0 else { throw DialerSkinError.openFailed }
            guard let dir = fdopendir(fd) else { close(fd); throw DialerSkinError.openFailed }
            defer { closedir(dir) }
            rewinddir(dir)
            while let entry = readdir(dir) {
                let name = withUnsafePointer(to: &entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
                }
                if name != "." && name != ".." { entries.append(name) }
            }
            return entries.sorted()
        }

        func read(_ name: String) throws -> File? {
            guard validName(name) else { throw DialerSkinError.invalidName }
            let fd = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            guard fd >= 0 else {
                if errno == ENOENT { return nil }
                throw DialerSkinError.openFailed
            }
            defer { close(fd) }
            var info = stat()
            guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
                  info.st_size >= 0, info.st_size <= maximumFile else { throw DialerSkinError.openFailed }
            let data = try FileHandle(fileDescriptor: fd, closeOnDealloc: false).read(upToCount: maximumFile + 1) ?? Data()
            var after = stat()
            guard data.count == info.st_size, fstat(fd, &after) == 0, after.st_size == info.st_size,
                  after.st_mtimespec.tv_sec == info.st_mtimespec.tv_sec,
                  after.st_mtimespec.tv_nsec == info.st_mtimespec.tv_nsec else { throw DialerSkinError.changed }
            var protection: Int32?
            #if os(iOS)
            let value = fcntl(fd, F_GETPROTECTIONCLASS)
            if value >= 0 { protection = value }
            #endif
            return File(data: data, device: UInt64(info.st_dev), inode: UInt64(info.st_ino),
                        mode: info.st_mode & 0o777, protection: protection)
        }

        func backup(_ name: String, file: File?, replacement: Data) throws {
            guard validName(name) else { throw DialerSkinError.invalidName }
            if let file {
                _ = try ContainerOriginals.prepare(in: directory, name: name, app: mobilePhoneBundleID,
                                                   kind: "dialer", path: name, original: file.data,
                                                   mode: file.mode, protection: file.protection,
                                                   current: file.data, replacement: replacement,
                                                   limit: maximumFile)
            } else {
                _ = try ContainerOriginals.prepare(in: directory, name: name, app: mobilePhoneBundleID,
                                                   kind: "dialer", path: name, original: Data(),
                                                   mode: 0o644, protection: nil, current: Data(),
                                                   replacement: replacement, limit: maximumFile,
                                                   originallyAbsent: true)
            }
        }

        func original(_ name: String) throws -> ContainerOriginals.Backup? {
            guard validName(name) else { throw DialerSkinError.invalidName }
            return try ContainerOriginals.read(in: directory, name: name, app: mobilePhoneBundleID,
                                               kind: "dialer", path: name, limit: maximumFile)
        }

        /// Atomically replaces a file through a temp file +
        /// `renameat`, mirroring `LaunchArtworkDirectory.replace`:
        /// the expected current file must still match (device,
        /// inode and bytes), the hierarchy is re-validated before
        /// and after the write, and the result is read back.
        /// `expected == nil` replaces unconditionally (a new file).
        func replace(_ name: String, expected: File?, data: Data, protection: Int32? = nil, mode: mode_t? = nil) throws {
            guard validName(name) else { throw DialerSkinError.invalidName }
            guard data.count <= maximumFile else { throw DialerSkinError.tooLarge }
            if let expected {
                guard let current = try read(name), current.data == expected.data,
                      current.device == expected.device, current.inode == expected.inode else {
                    throw DialerSkinError.changed
                }
            }
            try validateHierarchy()
            let temporary = ".GestaltX-\(UUID().uuidString)"
            let fd = openat(directory, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard fd >= 0 else { throw DialerSkinError.openFailed }
            defer { close(fd); unlinkat(directory, temporary, 0) }
            try data.withUnsafeBytes { bytes in
                var offset = 0
                while offset < bytes.count {
                    let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                    if count < 0, errno == EINTR { continue }
                    guard count > 0 else { throw DialerSkinError.openFailed }
                    offset += count
                }
            }
            let currentMode = (try? read(name))?.mode ?? 0o644
            guard fchmod(fd, mode ?? currentMode) == 0 else { throw DialerSkinError.openFailed }
            #if os(iOS)
            if let value = protection ?? (try? read(name))?.protection {
                guard fcntl(fd, F_SETPROTECTIONCLASS, value) == 0 else { throw DialerSkinError.openFailed }
            }
            #endif
            guard fsync(fd) == 0 else { throw DialerSkinError.openFailed }
            try validateHierarchy()
            if let expected {
                guard let latest = try read(name), latest.inode == expected.inode, latest.device == expected.device,
                      latest.data == expected.data else { throw DialerSkinError.changed }
            }
            guard renameat(directory, temporary, directory, name) == 0 else { throw DialerSkinError.openFailed }
            guard let written = try read(name), written.data == data else { throw DialerSkinError.changed }
        }

        /// Removes a file after verifying it still matches
        /// `expected` (device, inode and bytes).
        func remove(_ name: String, expected: File) throws {
            guard validName(name) else { throw DialerSkinError.invalidName }
            guard let current = try read(name), current.data == expected.data,
                  current.device == expected.device, current.inode == expected.inode else {
                throw DialerSkinError.changed
            }
            guard unlinkat(directory, name, 0) == 0 else { throw DialerSkinError.openFailed }
            guard (try? read(name)) == nil else { throw DialerSkinError.changed }
        }

        private func validateHierarchy() throws {
            for (index, component) in components.enumerated() {
                var path = stat(), pinned = stat()
                guard fstatat(descriptors[index], component, &path, AT_SYMLINK_NOFOLLOW) == 0,
                      fstat(descriptors[index + 1], &pinned) == 0,
                      (path.st_mode & S_IFMT) == S_IFDIR, path.st_dev == pinned.st_dev,
                      path.st_ino == pinned.st_ino else { throw DialerSkinError.changed }
            }
        }

        private func validName(_ name: String) -> Bool {
            !name.isEmpty && !name.contains("/") && !name.contains("\\0") && name.utf8.count + 4 <= 255
        }
    }

    enum DialerSkinError: LocalizedError, Equatable {
        case openFailed
        case invalidName
        case tooLarge
        case changed
        case containerNotFound
        case invalidTheme(String)

        var errorDescription: String? {
            switch self {
            case .openFailed: return "Could not open the Phone keypad directory."
            case .invalidName: return "Invalid keypad file name."
            case .tooLarge: return "Keypad image is too large."
            case .changed: return "The keypad files changed. Read again before applying."
            case .containerNotFound: return "The Phone app container could not be found."
            case .invalidTheme(let reason): return reason
            }
        }
    }

    /// Applies custom images for the given keys into the Phone
    /// container. Keys with empty or invalid data are skipped and
    /// counted as failures. Every overwritten file is backed up
    /// first; a failure mid-apply restores what was already written.
    /// Returns `(applied, failed)`. `container` is injectable for
    /// tests (a temp directory standing in for the Phone container).
    @discardableResult
    static func apply(images: [KeypadID: Data], container: URL) throws -> (applied: Int, failed: Int) {
        let directory = try Directory(container: container)
        let prefix = regCode(from: (try? directory.names()) ?? [])
        var applied = 0
        var failed = 0
        var written: [(name: String, before: Directory.File?)] = []
        do {
            for (key, data) in images {
                guard !data.isEmpty else { continue }
                guard isValidPNGData(data) else { failed += 1; continue }
                for name in key.fileNames(withPrefix: prefix) {
                    let before = try directory.read(name)
                    try directory.backup(name, file: before, replacement: data)
                    try directory.replace(name, expected: before, data: data,
                                          protection: before?.protection, mode: before?.mode)
                    written.append((name: name, before: before))
                    applied += 1
                }
            }
        } catch {
            for (name, before) in written.reversed() {
                if let before {
                    try? directory.replace(name, expected: (try? directory.read(name)) ?? before,
                                           data: before.data, protection: before.protection, mode: before.mode)
                } else if let current = try? directory.read(name) {
                    // The file did not exist before the apply; remove
                    // the file that was just created.
                    try? directory.remove(name, expected: current)
                }
            }
            throw error
        }
        return (applied, failed)
    }

    /// Restores every keypad file that has a matching `.bak`
    /// original and currently differs from it. Files that were
    /// originally absent are deleted instead of written back.
    /// Returns the number of files restored. Backups are retained,
    /// as with launch images, so a restore can be re-applied.
    @discardableResult
    static func restore(container: URL) throws -> Int {
        let directory = try Directory(container: container)
        var restored = 0
        for name in try directory.names() where name.hasSuffix(".png") {
            guard let file = try directory.read(name),
                  let saved = try directory.original(name),
                  saved.matches(file.data), saved.data != file.data else { continue }
            if saved.originallyAbsent {
                try directory.remove(name, expected: file)
            } else {
                try directory.replace(name, expected: file, data: saved.data,
                                      protection: saved.protection, mode: saved.mode)
            }
            restored += 1
        }
        return restored
    }

    /// Reads the current keypad artwork for every key (light/dark
    /// file per the given appearance). Missing files read as `nil`.
    static func currentKeypads(container: URL, dark: Bool) throws -> [KeypadID: Data] {
        let directory = try Directory(container: container)
        let prefix = regCode(from: (try? directory.names()) ?? [])
        var out: [KeypadID: Data] = [:]
        for key in KeypadID.allCases {
            let name = key.accentedFileName(withPrefix: prefix, dark: dark)
            if let file = try directory.read(name) {
                out[key] = file.data
            }
        }
        return out
    }

    /// Locates the Phone app container (device-only; `nil` on the
    /// simulator) and grants read access to it.
    static func phoneContainer() -> URL? {
        #if os(iOS) && !targetEnvironment(simulator)
        guard let path = GXCustomizationAccess.applicationContainer(for: mobilePhoneBundleID, hint: nil),
              !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        guard ContainerAccess.grantAccess(path: url.path, requireWrite: false).granted else { return nil }
        return url
        #else
        return nil
        #endif
    }

    /// Imports a dialer theme `.zip`: validates every entry stays
    /// inside the extraction directory (path-traversal guard),
    /// finds the `TelephonyUI-8/9/10` folder (or loose PNGs),
    /// and matches files to keys by key number + appearance
    /// (`mask` for light, `white` for dark). Returns key → PNG data.
    /// Throws `DialerSkinError.invalidTheme` on any problem.
    static func importTheme(from zipURL: URL, dark: Bool) throws -> [KeypadID: Data] {
        let fm = FileManager.default
        let tempURL = fm.temporaryDirectory.appendingPathComponent("ImportedKeypad_\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: tempURL) }
        guard let archive = try? Archive(url: zipURL, accessMode: .read) else {
            throw DialerSkinError.invalidTheme("Could not read the dialer theme archive.")
        }
        let destPrefix = tempURL.standardizedFileURL.path.hasSuffix("/")
            ? tempURL.standardizedFileURL.path : tempURL.standardizedFileURL.path + "/"
        for entry in archive {
            let entryPath = entry.path
            if entryPath.hasPrefix("/") || entryPath.split(separator: "/").contains("..")
                || entryPath.split(separator: "\\").contains("..") {
                throw DialerSkinError.invalidTheme("Theme archive contains an illegal path entry (\(entryPath)); import refused.")
            }
            let resolved = tempURL.standardizedFileURL.appendingPathComponent(entryPath).standardizedFileURL.path
            if resolved != tempURL.standardizedFileURL.path && !resolved.hasPrefix(destPrefix) {
                throw DialerSkinError.invalidTheme("Theme archive entry escapes the extraction directory (\(entryPath)); import refused.")
            }
        }
        try fm.createDirectory(at: tempURL, withIntermediateDirectories: true)
        try fm.unzipItem(at: zipURL, to: tempURL)
        var filesURL = tempURL
        let dirURLs = try fm.contentsOfDirectory(at: tempURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            .filter { $0.lastPathComponent != "__MACOSX" }
        if dirURLs.count == 1 {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: dirURLs[0].path, isDirectory: &isDir), isDir.boolValue {
                filesURL = dirURLs[0]
            }
        } else if let index = dirURLs.firstIndex(where: {
            ["TelephonyUI-8", "TelephonyUI-9", "TelephonyUI-10"].contains($0.lastPathComponent)
        }) {
            filesURL = dirURLs[index]
        } else if !dirURLs.contains(where: { $0.pathExtension.lowercased() == "png" }) {
            throw DialerSkinError.invalidTheme("No TelephonyUI folder or PNG files found in the theme archive.")
        }
        let fileURLs = try fm.contentsOfDirectory(at: filesURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            .filter { !$0.lastPathComponent.contains("-hi-") }
        let preferredAppearance = dark ? "white" : "mask"
        func matchFiles(acceptedAppearances: Set<String>) throws -> [KeypadID: Data] {
            var out: [KeypadID: Data] = [:]
            for itemURL in fileURLs {
                let split = itemURL.lastPathComponent.split(separator: "-").map(String.init)
                let appearance: String = {
                    if split.indices.contains(3) {
                        let part = String(split[3].split(separator: ".")[0])
                        if acceptedAppearances.contains(part) { return split[3] }
                    }
                    if split.indices.contains(2) {
                        let part = String(split[2].split(separator: ".")[0])
                        if acceptedAppearances.contains(part) { return split[2] }
                    }
                    return ""
                }()
                guard !appearance.isEmpty, split.indices.contains(1) else { continue }
                let keyNum = split[1]
                if let id = KeypadID.allCases.first(where: { $0.keyNumber == keyNum }), out[id] == nil {
                    let data = try Data(contentsOf: itemURL)
                    guard isValidPNGData(data) else { continue }
                    out[id] = data
                }
            }
            return out
        }
        var matched = try matchFiles(acceptedAppearances: [preferredAppearance])
        if matched.isEmpty {
            matched = try matchFiles(acceptedAppearances: ["mask", "white"])
        }
        guard !matched.isEmpty else {
            throw DialerSkinError.invalidTheme("The archive was extracted, but no keypad files were found.")
        }
        return matched
    }
}
