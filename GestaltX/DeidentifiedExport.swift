// SPDX-License-Identifier: GPL-3.0-only
// De-identified export (Stage 6, audit R-3): a plist export with
// the device-identifying values stripped, for sharing a plist
// without handing over this device's UDID and serial number.
//
// The result is unsealed and explicitly NOT restorable: it has no
// recorded digest and no `DeviceBoundPlist` seal, and `restore`
// never accepts an unsealed document as a backup. Stripping is a
// pure function on plist bytes — it never reads the device, never
// touches a backup, and never writes anything.
import Foundation

enum DeidentifiedExportError: Error, LocalizedError {
    case notADictionaryPlist

    var errorDescription: String? {
        switch self {
        case .notADictionaryPlist: return L("The export is not a dictionary plist.")
        }
    }
}

enum DeidentifiedExport {
    /// The MG keys whose values identify this device, by their
    /// obfuscated plist name — and, for a local file that kept the
    /// readable names, by readable name too. The same three names
    /// `LoggingEngine.redact` masks:
    ///   UniqueDeviceID / re6Zb+zwFKJNlkQTUeT+/w
    ///   SerialNumber   / VasUgeSzVyHdB27g2XpN0g
    ///   UniqueChipID   / TF31PAB6aO8KAbPyNKSxKA
    static let identityKeys: Set<String> = [
        "re6Zb+zwFKJNlkQTUeT+/w", "UniqueDeviceID",
        "VasUgeSzVyHdB27g2XpN0g", "SerialNumber",
        "TF31PAB6aO8KAbPyNKSxKA", "UniqueChipID",
    ]

    /// The de-identified file name for a full export of the same
    /// document.
    static let fileName = "MobileGestalt-LilaShift-deidentified.plist"

    /// Returns the plist with the identity keys removed, plus the
    /// plist keys that were actually removed (sorted). Keys that
    /// were absent are not listed. Throws when the data is not a
    /// dictionary plist. The round trip preserves every other key
    /// and value byte-for-byte in meaning (binary plist in,
    /// binary plist out).
    static func strip(_ data: Data) throws -> (data: Data, removed: [String]) {
        var format = PropertyListSerialization.PropertyListFormat.binary
        guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: &format) as? [String: Any] else {
            throw DeidentifiedExportError.notADictionaryPlist
        }
        var dict = plist
        var removed: [String] = []
        for key in identityKeys where dict[key] != nil {
            dict.removeValue(forKey: key)
            removed.append(key)
        }
        let stripped = try PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
        return (stripped, removed.sorted())
    }
}
