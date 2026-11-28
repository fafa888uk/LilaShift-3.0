// SPDX-License-Identifier: GPL-3.0-only
// Device Diagnostics (W1, LilaShift 5.0.0) — five new read-only
// diagnostics ported from the DeviceKit audit
// (audit/audit-devicekit-pulse-goldennugget-systemmonitor.md §1):
// screen physical metrics, biometric hardware, Low Power Mode,
// screen brightness and available disk capacity.
//
// Data sources — all public iOS APIs, no private API:
//   • Screen pixels / points / scale: `UIScreen` (live).
//   • PPI / diagonal / aspect ratio: a static per-model table
//     (see `DeviceKitModelTable`). PPI and diagonal cannot be read
//     from any public API; they come from the model table, and a
//     model that is not in the table honestly reports them as
//     unavailable instead of guessing.
//   • Biometrics: `LocalAuthentication` (`LAContext`, no prompt is
//     shown — `canEvaluatePolicy` only checks).
//   • Low Power Mode: `ProcessInfo.isLowPowerModeEnabled`.
//   • Brightness: `UIScreen.brightness`.
//   • Disk capacity: `FileManager` resource values
//     (`volumeAvailableCapacityForOpportunisticUsage` /
//     `volumeAvailableCapacityForImportantUsage` /
//     `volumeTotalCapacity`).
//   • Model identifier: `GXCopyPhysicalHardwareIdentity()`
//     (`hw.machine`, already bridged for Face ID recovery).
//
// Honesty rules, enforced by the types:
//   • Every value that cannot be read is `nil` with a reason, never
//     a guessed or simulated value.
//   • Display Zoom is derived from `nativeScale > scale` (see
//     `DeviceScreenMetrics.isZoomed`): on downsampled Plus models
//     nativeScale is SMALLER than scale in standard mode, so the
//     comparison must be `>`, not `!=`. This derivation must be
//     verified on a real device with Display Zoom toggled.
//   • Battery health / cycle count / capacity are NOT here: no
//     public API exposes them (see `BatteryStatus`).
//   • No system-wide CPU / memory / per-process figures: the iOS
//     sandbox does not expose them (see the audit §通则).
import Foundation
import LocalAuthentication
import UIKit

// MARK: - Model screen table (ported from DeviceKit, MIT)

// One model's fixed screen facts. The identifier is the
// `hw.machine` string (for example `iPhone18,4`); the pixel
// resolution, diagonal and PPI are that model's published Apple
// tech-spec values. The aspect ratio is computed from the pixels,
// never stored, so it cannot drift from the resolution.
struct DeviceModelScreenSpec: Equatable, Codable, Sendable {
    let identifier: String
    let modelName: String
    let diagonalInches: Double
    let pixelsPerInch: Int
    let pixelWidth: Int
    let pixelHeight: Int

    /// The aspect ratio as "19.5:9" / "16:9", computed from the
    /// pixel resolution (height / width, scaled to ":9" and rounded
    /// to one decimal). Whole ratios drop the ".0".
    var aspectRatioText: String {
        let ratio = Double(pixelHeight) / Double(pixelWidth) * 9.0
        let rounded = (ratio * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return "\(Int(rounded)):9"
        }
        return String(format: "%.1f:9", rounded)
    }
}

/// The identifier → model-name mapping ported from
/// devicekit/DeviceKit 5.10.0 (MIT, Copyright (c) 2015 Dennis
/// Weissmann — see W1NOTICES.md). Only the iPhone family is
/// ported: LilaShift is an iPhone tool, and every iPad / Apple TV /
///
/// Watch identifier honestly resolves to `nil` (unknown) rather
/// than to a guessed name. The screen values are the models'
/// published Apple tech-spec values, transcribed into the same
/// table so one lookup answers both the name and the PPI.
///
/// Scope notes, so a future reader does not mistake omissions for
/// errors:
///   • iPhone 18 (base) and iPhone Duo (`iPhone19,x` other than
///     `iPhone19,7`) are not in the table: their identifiers were
///     not verified at port time, so they stay unknown.
///   • `iPhone19,7` (iPhone 18 Pro Max, Global) and `iPhone18,4`
///     (iPhone Air) are in the table per the audit, but both still
///     need a real-device check (see records/w1-devicekit.md).
enum DeviceKitModelTable {
    static let sourceVersion = "5.10.0"
    static let sourceURL = "https://github.com/devicekit/DeviceKit"

    static let allSpecs: [DeviceModelScreenSpec] = [
        DeviceModelScreenSpec(identifier: "iPhone7,2", modelName: "iPhone 6", diagonalInches: 4.7, pixelsPerInch: 326, pixelWidth: 750, pixelHeight: 1334),
        DeviceModelScreenSpec(identifier: "iPhone7,1", modelName: "iPhone 6 Plus", diagonalInches: 5.5, pixelsPerInch: 401, pixelWidth: 1080, pixelHeight: 1920),
        DeviceModelScreenSpec(identifier: "iPhone8,1", modelName: "iPhone 6s", diagonalInches: 4.7, pixelsPerInch: 326, pixelWidth: 750, pixelHeight: 1334),
        DeviceModelScreenSpec(identifier: "iPhone8,2", modelName: "iPhone 6s Plus", diagonalInches: 5.5, pixelsPerInch: 401, pixelWidth: 1080, pixelHeight: 1920),
        DeviceModelScreenSpec(identifier: "iPhone8,4", modelName: "iPhone SE (1st generation)", diagonalInches: 4.0, pixelsPerInch: 326, pixelWidth: 640, pixelHeight: 1136),
        DeviceModelScreenSpec(identifier: "iPhone9,1", modelName: "iPhone 7", diagonalInches: 4.7, pixelsPerInch: 326, pixelWidth: 750, pixelHeight: 1334),
        DeviceModelScreenSpec(identifier: "iPhone9,3", modelName: "iPhone 7", diagonalInches: 4.7, pixelsPerInch: 326, pixelWidth: 750, pixelHeight: 1334),
        DeviceModelScreenSpec(identifier: "iPhone9,2", modelName: "iPhone 7 Plus", diagonalInches: 5.5, pixelsPerInch: 401, pixelWidth: 1080, pixelHeight: 1920),
        DeviceModelScreenSpec(identifier: "iPhone9,4", modelName: "iPhone 7 Plus", diagonalInches: 5.5, pixelsPerInch: 401, pixelWidth: 1080, pixelHeight: 1920),
        DeviceModelScreenSpec(identifier: "iPhone10,1", modelName: "iPhone 8", diagonalInches: 4.7, pixelsPerInch: 326, pixelWidth: 750, pixelHeight: 1334),
        DeviceModelScreenSpec(identifier: "iPhone10,4", modelName: "iPhone 8", diagonalInches: 4.7, pixelsPerInch: 326, pixelWidth: 750, pixelHeight: 1334),
        DeviceModelScreenSpec(identifier: "iPhone10,2", modelName: "iPhone 8 Plus", diagonalInches: 5.5, pixelsPerInch: 401, pixelWidth: 1080, pixelHeight: 1920),
        DeviceModelScreenSpec(identifier: "iPhone10,5", modelName: "iPhone 8 Plus", diagonalInches: 5.5, pixelsPerInch: 401, pixelWidth: 1080, pixelHeight: 1920),
        DeviceModelScreenSpec(identifier: "iPhone10,3", modelName: "iPhone X", diagonalInches: 5.8, pixelsPerInch: 458, pixelWidth: 1125, pixelHeight: 2436),
        DeviceModelScreenSpec(identifier: "iPhone10,6", modelName: "iPhone X", diagonalInches: 5.8, pixelsPerInch: 458, pixelWidth: 1125, pixelHeight: 2436),
        DeviceModelScreenSpec(identifier: "iPhone11,2", modelName: "iPhone XS", diagonalInches: 5.8, pixelsPerInch: 458, pixelWidth: 1125, pixelHeight: 2436),
        DeviceModelScreenSpec(identifier: "iPhone11,4", modelName: "iPhone XS Max", diagonalInches: 6.5, pixelsPerInch: 458, pixelWidth: 1242, pixelHeight: 2688),
        DeviceModelScreenSpec(identifier: "iPhone11,6", modelName: "iPhone XS Max", diagonalInches: 6.5, pixelsPerInch: 458, pixelWidth: 1242, pixelHeight: 2688),
        DeviceModelScreenSpec(identifier: "iPhone11,8", modelName: "iPhone XR", diagonalInches: 6.1, pixelsPerInch: 326, pixelWidth: 828, pixelHeight: 1792),
        DeviceModelScreenSpec(identifier: "iPhone12,1", modelName: "iPhone 11", diagonalInches: 6.1, pixelsPerInch: 326, pixelWidth: 828, pixelHeight: 1792),
        DeviceModelScreenSpec(identifier: "iPhone12,3", modelName: "iPhone 11 Pro", diagonalInches: 5.8, pixelsPerInch: 458, pixelWidth: 1125, pixelHeight: 2436),
        DeviceModelScreenSpec(identifier: "iPhone12,5", modelName: "iPhone 11 Pro Max", diagonalInches: 6.5, pixelsPerInch: 458, pixelWidth: 1242, pixelHeight: 2688),
        DeviceModelScreenSpec(identifier: "iPhone12,8", modelName: "iPhone SE (2nd generation)", diagonalInches: 4.7, pixelsPerInch: 326, pixelWidth: 750, pixelHeight: 1334),
        DeviceModelScreenSpec(identifier: "iPhone13,1", modelName: "iPhone 12 mini", diagonalInches: 5.4, pixelsPerInch: 476, pixelWidth: 1080, pixelHeight: 2340),
        DeviceModelScreenSpec(identifier: "iPhone13,2", modelName: "iPhone 12", diagonalInches: 6.1, pixelsPerInch: 460, pixelWidth: 1170, pixelHeight: 2532),
        DeviceModelScreenSpec(identifier: "iPhone13,3", modelName: "iPhone 12 Pro", diagonalInches: 6.1, pixelsPerInch: 460, pixelWidth: 1170, pixelHeight: 2532),
        DeviceModelScreenSpec(identifier: "iPhone13,4", modelName: "iPhone 12 Pro Max", diagonalInches: 6.7, pixelsPerInch: 458, pixelWidth: 1284, pixelHeight: 2778),
        DeviceModelScreenSpec(identifier: "iPhone14,4", modelName: "iPhone 13 mini", diagonalInches: 5.4, pixelsPerInch: 476, pixelWidth: 1080, pixelHeight: 2340),
        DeviceModelScreenSpec(identifier: "iPhone14,5", modelName: "iPhone 13", diagonalInches: 6.1, pixelsPerInch: 460, pixelWidth: 1170, pixelHeight: 2532),
        DeviceModelScreenSpec(identifier: "iPhone14,2", modelName: "iPhone 13 Pro", diagonalInches: 6.1, pixelsPerInch: 460, pixelWidth: 1179, pixelHeight: 2556),
        DeviceModelScreenSpec(identifier: "iPhone14,3", modelName: "iPhone 13 Pro Max", diagonalInches: 6.7, pixelsPerInch: 460, pixelWidth: 1284, pixelHeight: 2778),
        DeviceModelScreenSpec(identifier: "iPhone14,6", modelName: "iPhone SE (3rd generation)", diagonalInches: 4.7, pixelsPerInch: 326, pixelWidth: 750, pixelHeight: 1334),
        DeviceModelScreenSpec(identifier: "iPhone14,7", modelName: "iPhone 14", diagonalInches: 6.1, pixelsPerInch: 460, pixelWidth: 1170, pixelHeight: 2532),
        DeviceModelScreenSpec(identifier: "iPhone14,8", modelName: "iPhone 14 Plus", diagonalInches: 6.7, pixelsPerInch: 458, pixelWidth: 1284, pixelHeight: 2778),
        DeviceModelScreenSpec(identifier: "iPhone15,2", modelName: "iPhone 14 Pro", diagonalInches: 6.1, pixelsPerInch: 460, pixelWidth: 1179, pixelHeight: 2556),
        DeviceModelScreenSpec(identifier: "iPhone15,3", modelName: "iPhone 14 Pro Max", diagonalInches: 6.7, pixelsPerInch: 460, pixelWidth: 1290, pixelHeight: 2796),
        DeviceModelScreenSpec(identifier: "iPhone15,4", modelName: "iPhone 15", diagonalInches: 6.1, pixelsPerInch: 460, pixelWidth: 1179, pixelHeight: 2556),
        DeviceModelScreenSpec(identifier: "iPhone15,5", modelName: "iPhone 15 Plus", diagonalInches: 6.7, pixelsPerInch: 460, pixelWidth: 1290, pixelHeight: 2796),
        DeviceModelScreenSpec(identifier: "iPhone16,1", modelName: "iPhone 15 Pro", diagonalInches: 6.1, pixelsPerInch: 460, pixelWidth: 1179, pixelHeight: 2556),
        DeviceModelScreenSpec(identifier: "iPhone16,2", modelName: "iPhone 15 Pro Max", diagonalInches: 6.7, pixelsPerInch: 460, pixelWidth: 1290, pixelHeight: 2796),
        DeviceModelScreenSpec(identifier: "iPhone17,3", modelName: "iPhone 16", diagonalInches: 6.1, pixelsPerInch: 460, pixelWidth: 1179, pixelHeight: 2556),
        DeviceModelScreenSpec(identifier: "iPhone17,4", modelName: "iPhone 16 Plus", diagonalInches: 6.7, pixelsPerInch: 460, pixelWidth: 1290, pixelHeight: 2796),
        DeviceModelScreenSpec(identifier: "iPhone17,1", modelName: "iPhone 16 Pro", diagonalInches: 6.3, pixelsPerInch: 460, pixelWidth: 1206, pixelHeight: 2622),
        DeviceModelScreenSpec(identifier: "iPhone17,2", modelName: "iPhone 16 Pro Max", diagonalInches: 6.9, pixelsPerInch: 460, pixelWidth: 1320, pixelHeight: 2868),
        DeviceModelScreenSpec(identifier: "iPhone17,5", modelName: "iPhone 16e", diagonalInches: 6.1, pixelsPerInch: 460, pixelWidth: 1170, pixelHeight: 2532),
        DeviceModelScreenSpec(identifier: "iPhone18,3", modelName: "iPhone 17", diagonalInches: 6.3, pixelsPerInch: 460, pixelWidth: 1206, pixelHeight: 2622),
        DeviceModelScreenSpec(identifier: "iPhone18,1", modelName: "iPhone 17 Pro", diagonalInches: 6.3, pixelsPerInch: 460, pixelWidth: 1206, pixelHeight: 2622),
        DeviceModelScreenSpec(identifier: "iPhone18,2", modelName: "iPhone 17 Pro Max", diagonalInches: 6.9, pixelsPerInch: 460, pixelWidth: 1320, pixelHeight: 2868),
        DeviceModelScreenSpec(identifier: "iPhone18,4", modelName: "iPhone Air", diagonalInches: 6.5, pixelsPerInch: 460, pixelWidth: 1260, pixelHeight: 2736),
        DeviceModelScreenSpec(identifier: "iPhone18,5", modelName: "iPhone 17e", diagonalInches: 6.1, pixelsPerInch: 460, pixelWidth: 1170, pixelHeight: 2532),
        DeviceModelScreenSpec(identifier: "iPhone19,7", modelName: "iPhone 18 Pro Max", diagonalInches: 6.9, pixelsPerInch: 460, pixelWidth: 1320, pixelHeight: 2868),
    ]

    /// The spec for one `hw.machine` identifier, or `nil` when the
    /// model is not in the table. `nil` is a real answer (unknown),
    /// never a guessed model.
    static func spec(forIdentifier identifier: String) -> DeviceModelScreenSpec? {
        allSpecs.first { $0.identifier == identifier }
    }

    /// The model name for one identifier, or `nil` when unknown.
    static func modelName(forIdentifier identifier: String) -> String? {
        spec(forIdentifier: identifier)?.modelName
    }
}

// MARK: - Screen metrics

/// The live screen readings plus the static per-model facts.
/// Pixel / point sizes, scale and nativeScale always come from
/// `UIScreen`; PPI, diagonal and aspect ratio come from the model
/// table and are `nil` for an unmapped model.
struct DeviceScreenMetrics: Equatable, Sendable {
    let identifier: String?
    let spec: DeviceModelScreenSpec?
    let pointsWidth: Double
    let pointsHeight: Double
    let pixelWidth: Int
    let pixelHeight: Int
    let scale: Double
    let nativeScale: Double

    var modelName: String? { spec?.modelName }
    var diagonalInches: Double? { spec?.diagonalInches }
    var pixelsPerInch: Int? { spec?.pixelsPerInch }
    var aspectRatioText: String? { spec?.aspectRatioText }

    /// Display Zoom is on when the screen renders fewer points
    /// than the physical panel holds, which shows up as the native
    /// scale exceeding the current scale. The comparison is `>`,
    /// not `!=`: on downsampled Plus models the native scale is
    /// SMALLER than the scale (2.608 vs 3.0) in standard mode, so
    /// `!=` would falsely report zoom there. This derivation must
    /// be verified on a real device with Display Zoom toggled.
    var isZoomed: Bool { nativeScale > scale }

    /// Why the model facts are missing, or `nil` when the model is
    /// mapped. The live pixel / point readings are unaffected.
    var unmappedIdentifierReason: String? {
        guard spec == nil else { return nil }
        if let identifier {
            return L("Model not in the screen table") + ": " + identifier
        }
        return L("The device model could not be identified.")
    }

    /// Pure mapping from injected readings, so tests can cover the
    /// table lookup and the zoom derivation without a screen.
    static func from(
        identifier: String?, points: CGSize, pixels: CGSize,
        scale: Double, nativeScale: Double
    ) -> DeviceScreenMetrics {
        DeviceScreenMetrics(
            identifier: identifier,
            spec: identifier.flatMap { DeviceKitModelTable.spec(forIdentifier: $0) },
            pointsWidth: Double(points.width),
            pointsHeight: Double(points.height),
            pixelWidth: Int(pixels.width.rounded()),
            pixelHeight: Int(pixels.height.rounded()),
            scale: scale,
            nativeScale: nativeScale)
    }
}

// MARK: - Biometric hardware

/// Which biometric sensor the hardware has, from
/// `LAContext.biometryType`. `.none` means the device reports no
/// Face ID or Touch ID sensor (including the simulator).
enum BiometricKind: String, Equatable, Codable, Sendable {
    case faceID
    case touchID
    /// visionOS Optic ID (iris authentication). LilaShift runs on
    /// iPhone, where this never occurs, but it is a real biometric
    /// sensor — it must not be reported as "no hardware" (`.none`).
    case opticID
    case none

    var title: String {
        switch self {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        case .none: return L("None")
        }
    }
}

/// The biometric hardware state. `canEvaluate` is whether a
/// biometric check could run right now; `detail` explains why not
/// (not enrolled, locked out, no sensor) or is `nil` when the
/// sensor is present and usable. Checking never prompts the user.
struct BiometricStatus: Equatable, Sendable {
    let kind: BiometricKind
    let canEvaluate: Bool
    let detail: String?

    /// Pure mapping from injected `LAContext` readings, so tests
    /// can cover every branch without hardware.
    static func from(
        biometryType: LABiometryType, canEvaluate: Bool, error: NSError?
    ) -> BiometricStatus {
        let kind: BiometricKind
        switch biometryType {
        case .faceID: kind = .faceID
        case .touchID: kind = .touchID
        case .opticID: kind = .opticID
        case .none: kind = .none
        @unknown default: kind = .none
        }
        let detail: String?
        if canEvaluate {
            detail = nil
        } else if kind == .none {
            detail = L("No Face ID or Touch ID hardware was detected.")
        } else {
            detail = reason(for: error)
        }
        return BiometricStatus(kind: kind, canEvaluate: canEvaluate, detail: detail)
    }

    /// The human reason for a failed biometric check, from the
    /// `LAError` code. An error outside the LocalAuthentication
    /// domain falls back to its own description; `nil` stays `nil`.
    static func reason(for error: NSError?) -> String? {
        guard let error else { return nil }
        guard error.domain == LAError.errorDomain else {
            return error.localizedDescription
        }
        switch LAError.Code(rawValue: error.code) {
        case .biometryNotEnrolled:
            return L("No biometric is enrolled on this device.")
        case .biometryNotAvailable:
            return L("Biometric hardware is not available on this device.")
        case .biometryLockout:
            return L("Biometrics are locked out. Unlock with the device passcode first.")
        case .passcodeNotSet:
            return L("No device passcode is set.")
        default:
            return error.localizedDescription
        }
    }
}

// MARK: - Screen brightness

/// The screen brightness from `UIScreen.brightness`, clamped to
/// 0.0–1.0. This is the current brightness setting, not a sensor
/// reading of ambient light.
struct ScreenBrightness: Equatable, Sendable {
    let value: Double

    var percent: Int { Int((value * 100).rounded()) }

    static func from(_ raw: Double) -> ScreenBrightness {
        ScreenBrightness(value: min(max(raw, 0), 1))
    }
}

// MARK: - Disk capacity

/// Available disk capacity from `FileManager` resource values.
/// Opportunistic capacity is what the system can free for
/// nice-to-have downloads; important capacity is what is available
/// for files the user really needs; total is the volume size. All
/// three are `nil` with `unavailableReason` set when the read
/// itself fails — never zero, never guessed.
struct DiskCapacity: Equatable, Sendable {
    let opportunisticBytes: Int64?
    let importantBytes: Int64?
    let totalBytes: Int64?
    let unavailableReason: String?

    /// Pure mapping from injected values, so tests can cover the
    /// unavailable state without a volume.
    static func from(
        opportunistic: Int64?, important: Int64?, total: Int64?,
        unavailableReason: String? = nil
    ) -> DiskCapacity {
        DiskCapacity(
            opportunisticBytes: opportunistic, importantBytes: important,
            totalBytes: total, unavailableReason: unavailableReason)
    }

    /// The live read over the volume that holds `volumeURL`
    /// (default: the app's Documents directory). Read-only.
    static func read(volumeURL: URL? = nil) -> DiskCapacity {
        let url = volumeURL
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: "/")
        do {
            let values = try url.resourceValues(forKeys: [
                .volumeAvailableCapacityForOpportunisticUsageKey,
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeTotalCapacityKey,
            ])
            // Split into locals first: the single nested
            // `DiskCapacity(...)` expression is too complex for the
            // type checker ("failed to produce diagnostic for
            // expression"). Same values, same result.
            let opportunistic = values.volumeAvailableCapacityForOpportunisticUsage.map(Int64.init)
            let important = values.volumeAvailableCapacityForImportantUsage.map(Int64.init)
            let total = values.volumeTotalCapacity.map(Int64.init)
            return DiskCapacity(
                opportunisticBytes: opportunistic,
                importantBytes: important,
                totalBytes: total,
                unavailableReason: nil)
        } catch {
            return DiskCapacity(
                opportunisticBytes: nil, importantBytes: nil, totalBytes: nil,
                unavailableReason: error.localizedDescription)
        }
    }
}

// MARK: - Report and live reader

/// The five W1 diagnostics in one read, stamped with the read
/// time. Low Power Mode is a plain `Bool` from `ProcessInfo` — it
/// is always readable, so it carries no unavailable state.
struct DeviceDiagnosticsReport: Equatable, Sendable {
    let screenMetrics: DeviceScreenMetrics
    let biometrics: BiometricStatus
    let isLowPowerModeEnabled: Bool
    let brightness: ScreenBrightness
    let diskCapacity: DiskCapacity
    let measuredAt: Date
}

/// The live reader: `UIScreen`, `LAContext`, `ProcessInfo` and
/// `FileManager` (all public APIs). `UIScreen.main` must be read
/// on the main thread, so callers must call `read()` from the main
/// actor — the view does (its `refresh()` runs from `onAppear` /
/// button actions). The biometric check never prompts the user.
final class DeviceDiagnosticsReader {
    func read() -> DeviceDiagnosticsReport {
        let identifier = GXCopyPhysicalHardwareIdentity()["hw.machine"]
        let screen = UIScreen.main
        let screenMetrics = DeviceScreenMetrics.from(
            identifier: identifier,
            points: screen.bounds.size,
            pixels: screen.nativeBounds.size,
            scale: Double(screen.scale),
            nativeScale: Double(screen.nativeScale))
        let context = LAContext()
        var authError: NSError?
        let canEvaluate = context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics, error: &authError)
        let biometrics = BiometricStatus.from(
            biometryType: context.biometryType,
            canEvaluate: canEvaluate, error: authError)
        return DeviceDiagnosticsReport(
            screenMetrics: screenMetrics,
            biometrics: biometrics,
            isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
            brightness: ScreenBrightness.from(Double(screen.brightness)),
            diskCapacity: DiskCapacity.read(),
            measuredAt: Date())
    }
}
