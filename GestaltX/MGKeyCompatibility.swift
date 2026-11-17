// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Per-key compatibility evaluation for the monitor (Stage 4).
/// Reuses the existing `CompatibilityStatus` display model; the
/// precedence below is the Stage 4 piece, not a unification of the
/// two existing eligibility systems (that is out of scope).
///
/// Precedence — the first matching rule wins, and a rule that cannot
/// be decided honestly falls through to `unverified`, never to a
/// guessed state:
/// 1. Sentinel blocked → `.readFailed` ("not granted on this iOS version").
/// 2. Sentinel unknown → `.unverified` (the build could not be confirmed).
/// 3. Unknown product type → `.unverified` (scope cannot be checked).
/// 4. Out of device scope → `.unsupported`.
/// 5. Out of iOS scope → `.unsupported`.
/// 6. Not readable via MGCopyAnswer → `.unverified` (IODeviceTree query key).
/// 7. No live value → `.unverified` (absent on this device, or the
///    probe returned nothing — the two cannot be distinguished).
/// 8. Bool key: live true → `.enabled`; live false + writable →
///    `.modifiable`; live false + read-only → `.unsupported`.
/// 9. Non-bool key with a live value: equals the native default →
///    `.nativeSupported`; otherwise `.unverified` (informational —
///    the live value is shown, no enabled state applies).
enum MGKeyCompatibility {
    static func evaluate(record: MGKeyRecord, productType: String?, iosVersion: String,
                         live: MGValue?, sentinel: VersionSentinelState) -> (status: CompatibilityStatus, reason: String) {
        switch sentinel {
        case .blocked:
            return (.readFailed, L("Not granted on this iOS version."))
        case .unknownBuild:
            return (.unverified, L("The iOS build could not be confirmed."))
        case .supported:
            break
        }
        guard let productType else {
            return (.unverified, L("The device model is unknown, so scope cannot be checked."))
        }
        guard record.deviceScope.contains(productType: productType) else {
            return (.unsupported, L("This key does not apply to this device model."))
        }
        guard record.iosScope.contains(iosVersion) else {
            return (.unsupported, L("This key is not present in this iOS version."))
        }
        guard record.readableViaMGCopyAnswer else {
            return (.unverified, L("This key cannot be read with MGCopyAnswer (it is an IODeviceTree query key)."))
        }
        guard let live else {
            return (.unverified, L("No live value: the key may be absent on this device, or the probe returned nothing."))
        }
        if case .bool(let value) = live {
            if value { return (.enabled, L("Live value is on.")) }
            if record.writable { return (.modifiable, L("Live value is off; this key may be staged.")) }
            return (.unsupported, L("Live value is off; this key is read-only."))
        }
        if let defaultValue = record.defaultValue, live == defaultValue {
            return (.nativeSupported, L("Live value matches the native default."))
        }
        return (.unverified, L("Informational key: the live value is shown, no enabled state applies."))
    }
}
