// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Lock-screen device asset tag (A19).
///
/// `AssetTagInformation` is a native field of the system
/// configuration profile file `SharedDeviceConfiguration.plist`:
/// the text shown at the bottom of the Lock Screen (or in About)
/// as lost-and-found contact info or a device number. Mechanism
/// follows Erosion-CN's `ConfigView` (Kianuni, GPL-3.0),
/// reimplemented for LilaShift's access helper: the plist is read,
/// the one field is set or removed, and the file is written back
/// with every other key preserved. An empty value removes the field;
/// when the dictionary becomes empty the file itself is removed.
///
/// This modifies NO system binary and NO supervision flag: the
/// supervision file (`CloudConfigurationDetails.plist`) lives next
/// to this one and is never touched here — see `SupervisionAudit`.
/// The write goes through a worse_query read/write grant for the
/// configuration-profiles directory, writes atomically, and verifies
/// by reading the file back.
enum AssetTag {
    static let key = "AssetTagInformation"

    /// The current asset tag, or `nil` when the file or the field
    /// does not exist. `url` is injectable for tests.
    static func read(at url: URL = SupervisionAudit.sharedDeviceConfigurationURL) -> String? {
        _ = ContainerAccess.grantAccess(path: SupervisionAudit.configurationProfilesDirectory, requireWrite: false)
        guard let dict = NSDictionary(contentsOf: url) else { return nil }
        return dict[key] as? String
    }

    /// Sets the asset tag, or removes the field when `text` is empty
    /// after trimming. Preserves every other key in the plist.
    /// Returns `false` when the directory could not be granted for
    /// writing or the write could not be verified. A directory the
    /// app can already write (tests, or a directly readable path)
    /// needs no worse_query grant; the grant is only required for
    /// the real system configuration-profiles directory.
    @discardableResult
    static func apply(_ text: String, at url: URL = SupervisionAudit.sharedDeviceConfigurationURL) -> Bool {
        let fm = FileManager.default
        let dirURL = url.deletingLastPathComponent()
        if !fm.isWritableFile(atPath: dirURL.path) {
            let grant = ContainerAccess.grantAccess(path: SupervisionAudit.configurationProfilesDirectory, requireWrite: true)
            guard grant.granted else { return false }
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let dict = NSMutableDictionary(dictionary: (NSDictionary(contentsOf: url) as? [String: Any]) ?? [:])
            if trimmed.isEmpty {
                dict.removeObject(forKey: key)
            } else {
                dict[key] = trimmed
            }
            if dict.count == 0 {
                if fm.fileExists(atPath: url.path) {
                    try fm.removeItem(at: url)
                }
            } else {
                let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
                try data.write(to: url, options: .atomic)
            }
            // Verify by reading back.
            if dict.count == 0 {
                return !fm.fileExists(atPath: url.path)
            }
            guard let back = NSDictionary(contentsOf: url) else {
                return false
            }
            if trimmed.isEmpty {
                // Removing the tag: success means the key is gone.
                return back[key] == nil
            }
            return (back[key] as? String) == trimmed
        } catch {
            return false
        }
    }
}
