// SPDX-License-Identifier: GPL-3.0-only
// Central logging (Stage 3, ADR-2-04 / ADR-2-06).
//
// One subsystem, one logger per area, so log lines are attributable
// without every call site building its own Logger. Nothing in this
// file writes to disk or the network; it only forwards to os_log.
//
// `redact` masks device identifiers before a line is logged: the
// values of the three identity keys (by name and by MobileGestalt
// question hash), dashed UDIDs, standalone 40-hex UDIDs and standalone
// 12-hex serials. Model numbers, region codes and MobileGestalt keys
// are not device identifiers and pass through unchanged. The masking
// is deliberately broad: a log line must never leak a device identity
// because a call site forgot to redact first.
import Foundation
import os

enum LilaLog {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.huami.gestultx"
    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let staging = Logger(subsystem: subsystem, category: "staging")
    static let io = Logger(subsystem: subsystem, category: "io")
    static let diagnostics = Logger(subsystem: subsystem, category: "diagnostics")

    /// Device identifier keys, by display name and by their
    /// MobileGestalt question hash (DevicePlistIdentity.keys). The
    /// hashes are the same on every device — only the values are
    /// device-specific — so only values are masked, never the keys.
    private static let identifierKeys = [
        "UniqueDeviceID", "SerialNumber", "UniqueChipID",
        "re6Zb+zwFKJNlkQTUeT+/w", "VasUgeSzVyHdB27g2XpN0g", "TF31PAB6aO8KAbPyNKSxKA",
    ]

    /// Returns the text with device identifiers replaced by
    /// "[redacted]". Idempotent: redacting twice changes nothing.
    static func redact(_ text: String) -> String {
        var result = text
        // Identifier values after a key, either "Key=value" or
        // "Key: value" as written in log lines.
        for key in identifierKeys {
            let pattern = NSRegularExpression.escapedPattern(for: key) + "[=:]\\s*[^\\s,;]+"
            result = result.replacingOccurrences(of: pattern, with: key + "=[redacted]", options: .regularExpression)
        }
        // Dashed UDID ("00008150-000C0C5A14D2401C") and standalone
        // 40-hex UDIDs. The 12-hex rule runs last so it cannot match
        // inside a longer hex run: word boundaries only exist at the
        // ends of a token, never inside one.
        result = result.replacingOccurrences(of: "\\b[0-9a-fA-F]{8}-[0-9a-fA-F]{16}\\b", with: "[redacted]", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\b[0-9a-fA-F]{40}\\b", with: "[redacted]", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\b[0-9a-fA-F]{12}\\b", with: "[redacted]", options: .regularExpression)
        return result
    }
}
