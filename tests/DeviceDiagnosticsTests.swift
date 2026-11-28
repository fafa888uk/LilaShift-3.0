// SPDX-License-Identifier: GPL-3.0-only
// Tests for W1 DeviceKit diagnostics (LilaShift 5.0.0): the
// identifier → model screen table (ported from DeviceKit 5.10.0,
// MIT), the screen-metrics mapping including Display Zoom
// derivation, biometric hardware detection, Low Power Mode,
// brightness clamping, disk capacity reads, the report assembly
// and the W1 registration metadata.
//
// Every test here is pure or reads a real local volume: nothing
// is simulated, and no test touches the MobileGestalt cache. The
// live `DeviceDiagnosticsReader` (UIScreen / LAContext) is not
// unit-tested — it needs a real device and is covered by the
// real-device checklist in records/w1-devicekit.md.
import Foundation
import LocalAuthentication
import UIKit
import XCTest
@testable import GestaltX

final class DeviceDiagnosticsTests: XCTestCase {

    // MARK: - Model table

    func testIPhoneAirMapsToCorrectModelAndScreen() {
        let spec = DeviceKitModelTable.spec(forIdentifier: "iPhone18,4")
        XCTAssertEqual(spec?.modelName, "iPhone Air")
        XCTAssertEqual(spec?.diagonalInches, 6.5)
        XCTAssertEqual(spec?.pixelsPerInch, 460)
        XCTAssertEqual(spec?.pixelWidth, 1260)
        XCTAssertEqual(spec?.pixelHeight, 2736)
        XCTAssertEqual(spec?.aspectRatioText, "19.5:9")
        XCTAssertEqual(DeviceKitModelTable.modelName(forIdentifier: "iPhone18,4"), "iPhone Air")
    }

    func testIPhone18ProMaxMaps() {
        let spec = DeviceKitModelTable.spec(forIdentifier: "iPhone19,7")
        XCTAssertEqual(spec?.modelName, "iPhone 18 Pro Max")
        XCTAssertEqual(spec?.diagonalInches, 6.9)
        XCTAssertEqual(spec?.pixelsPerInch, 460)
        XCTAssertEqual(spec?.pixelWidth, 1320)
        XCTAssertEqual(spec?.pixelHeight, 2868)
        XCTAssertEqual(spec?.aspectRatioText, "19.6:9")
    }

    func testOlderModelsMap() {
        let x = DeviceKitModelTable.spec(forIdentifier: "iPhone10,3")
        XCTAssertEqual(x?.modelName, "iPhone X")
        XCTAssertEqual(x?.pixelsPerInch, 458)
        XCTAssertEqual(x?.pixelWidth, 1125)
        XCTAssertEqual(x?.pixelHeight, 2436)
        XCTAssertEqual(x?.aspectRatioText, "19.5:9")

        let fourteen = DeviceKitModelTable.spec(forIdentifier: "iPhone14,7")
        XCTAssertEqual(fourteen?.modelName, "iPhone 14")
        XCTAssertEqual(fourteen?.pixelsPerInch, 460)

        let se = DeviceKitModelTable.spec(forIdentifier: "iPhone8,4")
        XCTAssertEqual(se?.modelName, "iPhone SE (1st generation)")
        XCTAssertEqual(se?.diagonalInches, 4.0)
        XCTAssertEqual(se?.pixelsPerInch, 326)
        XCTAssertEqual(se?.pixelWidth, 640)
        XCTAssertEqual(se?.pixelHeight, 1136)
        XCTAssertEqual(se?.aspectRatioText, "16:9")
    }

    /// Unknown identifiers — a future iPhone, an iPad, or an empty
    /// string — resolve to `nil`, never to a guessed model. The
    /// iPad family is deliberately not ported (see
    /// `DeviceKitModelTable`).
    func testUnknownIdentifierIsNilNotGuessed() {
        XCTAssertNil(DeviceKitModelTable.spec(forIdentifier: "iPhone99,9"))
        XCTAssertNil(DeviceKitModelTable.modelName(forIdentifier: "iPhone99,9"))
        XCTAssertNil(DeviceKitModelTable.spec(forIdentifier: "iPad13,1"))
        XCTAssertNil(DeviceKitModelTable.spec(forIdentifier: ""))
    }

    /// A duplicated identifier in the table would make the lookup
    /// ambiguous: the table must carry each identifier once.
    func testTableIdentifiersAreUnique() {
        let identifiers = DeviceKitModelTable.allSpecs.map(\.identifier)
        XCTAssertEqual(Set(identifiers).count, identifiers.count)
        XCTAssertFalse(identifiers.isEmpty)
    }

    /// Every table entry must be physically sane: portrait pixels,
    /// a real diagonal, and a PPI Apple actually shipped.
    func testTableSpecsAreSane() {
        for spec in DeviceKitModelTable.allSpecs {
            XCTAssertGreaterThan(spec.pixelWidth, 0, spec.identifier)
            XCTAssertGreaterThan(spec.pixelHeight, spec.pixelWidth, spec.identifier)
            XCTAssertGreaterThan(spec.diagonalInches, 0, spec.identifier)
            XCTAssertLessThanOrEqual(spec.diagonalInches, 7.0, spec.identifier)
            XCTAssertTrue([326, 401, 458, 460, 476].contains(spec.pixelsPerInch), spec.identifier)
            XCTAssertFalse(spec.modelName.isEmpty, spec.identifier)
        }
    }

    func testAspectRatioTextIsComputedFromPixels() {
        let pro = DeviceKitModelTable.spec(forIdentifier: "iPhone17,1")
        XCTAssertEqual(pro?.aspectRatioText, "19.6:9")
        let eight = DeviceKitModelTable.spec(forIdentifier: "iPhone10,1")
        XCTAssertEqual(eight?.aspectRatioText, "16:9")
        let mini = DeviceKitModelTable.spec(forIdentifier: "iPhone13,1")
        XCTAssertEqual(mini?.aspectRatioText, "19.5:9")
    }

    // MARK: - Screen metrics

    func testScreenMetricsFromKnownModel() {
        let metrics = DeviceScreenMetrics.from(
            identifier: "iPhone18,4",
            points: CGSize(width: 420, height: 912),
            pixels: CGSize(width: 1260, height: 2736),
            scale: 3.0, nativeScale: 3.0)
        XCTAssertEqual(metrics.modelName, "iPhone Air")
        XCTAssertEqual(metrics.diagonalInches, 6.5)
        XCTAssertEqual(metrics.pixelsPerInch, 460)
        XCTAssertEqual(metrics.aspectRatioText, "19.5:9")
        XCTAssertEqual(metrics.pointsWidth, 420)
        XCTAssertEqual(metrics.pointsHeight, 912)
        XCTAssertEqual(metrics.pixelWidth, 1260)
        XCTAssertEqual(metrics.pixelHeight, 2736)
        XCTAssertFalse(metrics.isZoomed)
        XCTAssertNil(metrics.unmappedIdentifierReason)
    }

    /// An unmapped model still reports the live readings; only the
    /// table facts (PPI, size, ratio) are unavailable, with the
    /// identifier named in the reason.
    func testScreenMetricsUnknownModelKeepsLiveReadings() {
        let metrics = DeviceScreenMetrics.from(
            identifier: "iPhone99,9",
            points: CGSize(width: 420, height: 912),
            pixels: CGSize(width: 1260, height: 2736),
            scale: 3.0, nativeScale: 3.0)
        XCTAssertNil(metrics.modelName)
        XCTAssertNil(metrics.diagonalInches)
        XCTAssertNil(metrics.pixelsPerInch)
        XCTAssertNil(metrics.aspectRatioText)
        XCTAssertEqual(metrics.pixelWidth, 1260)
        XCTAssertEqual(metrics.pixelHeight, 2736)
        XCTAssertNotNil(metrics.unmappedIdentifierReason)
        XCTAssertTrue(metrics.unmappedIdentifierReason?.contains("iPhone99,9") ?? false)
    }

    func testScreenMetricsNilIdentifierHasReason() {
        let metrics = DeviceScreenMetrics.from(
            identifier: nil,
            points: CGSize(width: 390, height: 844),
            pixels: CGSize(width: 1170, height: 2532),
            scale: 3.0, nativeScale: 3.0)
        XCTAssertNil(metrics.modelName)
        XCTAssertEqual(metrics.pixelWidth, 1170)
        XCTAssertNotNil(metrics.unmappedIdentifierReason)
    }

    /// Display Zoom is `nativeScale > scale`, not `!=`: a zoomed
    /// screen renders fewer points than the panel holds, while a
    /// downsampled Plus model has nativeScale SMALLER than scale
    /// (2.608 vs 3.0) in standard mode and must not read as zoomed.
    func testDisplayZoomDerivation() {
        let zoomed = DeviceScreenMetrics.from(
            identifier: "iPhone15,3",
            points: CGSize(width: 402, height: 874),
            pixels: CGSize(width: 1290, height: 2796),
            scale: 2.88, nativeScale: 3.0)
        XCTAssertTrue(zoomed.isZoomed)

        let standard = DeviceScreenMetrics.from(
            identifier: "iPhone15,3",
            points: CGSize(width: 430, height: 932),
            pixels: CGSize(width: 1290, height: 2796),
            scale: 3.0, nativeScale: 3.0)
        XCTAssertFalse(standard.isZoomed)

        let plusStandard = DeviceScreenMetrics.from(
            identifier: "iPhone10,2",
            points: CGSize(width: 414, height: 736),
            pixels: CGSize(width: 1080, height: 1920),
            scale: 3.0, nativeScale: 2.608)
        XCTAssertFalse(plusStandard.isZoomed, "A downsampled Plus model in standard mode is not zoomed")
    }

    // MARK: - Biometrics

    func testBiometricsFaceIDUsable() {
        let status = BiometricStatus.from(biometryType: .faceID, canEvaluate: true, error: nil)
        XCTAssertEqual(status.kind, .faceID)
        XCTAssertEqual(status.kind.title, "Face ID")
        XCTAssertTrue(status.canEvaluate)
        XCTAssertNil(status.detail)
    }

    func testBiometricsTouchIDNotEnrolled() {
        let error = LAError(.biometryNotEnrolled) as NSError
        let status = BiometricStatus.from(biometryType: .touchID, canEvaluate: false, error: error)
        XCTAssertEqual(status.kind, .touchID)
        XCTAssertEqual(status.kind.title, "Touch ID")
        XCTAssertFalse(status.canEvaluate)
        XCTAssertEqual(status.detail, "No biometric is enrolled on this device.")
    }

    func testBiometricsNoSensor() {
        let status = BiometricStatus.from(biometryType: .none, canEvaluate: false, error: nil)
        XCTAssertEqual(status.kind, .none)
        XCTAssertEqual(status.kind.title, "None")
        XCTAssertFalse(status.canEvaluate)
        XCTAssertNotNil(status.detail)
        XCTAssertTrue(status.detail?.contains("No Face ID or Touch ID hardware") ?? false)
    }

    func testBiometricsLockout() {
        let error = LAError(.biometryLockout) as NSError
        let status = BiometricStatus.from(biometryType: .faceID, canEvaluate: false, error: error)
        XCTAssertFalse(status.canEvaluate)
        XCTAssertNotNil(status.detail)
        XCTAssertTrue(status.detail?.contains("locked out") ?? false)
    }

    func testBiometricReasonMapping() {
        XCTAssertNil(BiometricStatus.reason(for: nil))
        XCTAssertEqual(
            BiometricStatus.reason(for: LAError(.biometryNotAvailable) as NSError),
            "Biometric hardware is not available on this device.")
        XCTAssertEqual(
            BiometricStatus.reason(for: LAError(.passcodeNotSet) as NSError),
            "No device passcode is set.")
        let foreign = NSError(
            domain: "com.example.test", code: 7,
            userInfo: [NSLocalizedDescriptionKey: "custom reason"])
        XCTAssertEqual(BiometricStatus.reason(for: foreign), "custom reason")
    }

    // MARK: - Brightness

    func testBrightnessPercentAndClamping() {
        XCTAssertEqual(ScreenBrightness.from(0.5).percent, 50)
        XCTAssertEqual(ScreenBrightness.from(1.5).value, 1.0)
        XCTAssertEqual(ScreenBrightness.from(1.5).percent, 100)
        XCTAssertEqual(ScreenBrightness.from(-0.2).value, 0.0)
        XCTAssertEqual(ScreenBrightness.from(-0.2).percent, 0)
        XCTAssertEqual(ScreenBrightness.from(0.333).percent, 33)
    }

    // MARK: - Disk capacity

    func testDiskCapacityFromValues() {
        let capacity = DiskCapacity.from(
            opportunistic: 1_000, important: 2_000, total: 64_000_000_000)
        XCTAssertEqual(capacity.opportunisticBytes, 1_000)
        XCTAssertEqual(capacity.importantBytes, 2_000)
        XCTAssertEqual(capacity.totalBytes, 64_000_000_000)
        XCTAssertNil(capacity.unavailableReason)
    }

    func testDiskCapacityUnavailableState() {
        let capacity = DiskCapacity.from(
            opportunistic: nil, important: nil, total: nil,
            unavailableReason: "volume not found")
        XCTAssertNil(capacity.opportunisticBytes)
        XCTAssertNil(capacity.importantBytes)
        XCTAssertNil(capacity.totalBytes)
        XCTAssertEqual(capacity.unavailableReason, "volume not found")
    }

    /// A real read over a real volume: the temp directory's volume
    /// must report positive available and total capacity.
    func testDiskCapacityLiveReadFromTempDirectory() {
        let capacity = DiskCapacity.read(volumeURL: FileManager.default.temporaryDirectory)
        XCTAssertNil(capacity.unavailableReason)
        XCTAssertNotNil(capacity.opportunisticBytes)
        XCTAssertNotNil(capacity.totalBytes)
        XCTAssertGreaterThan(capacity.opportunisticBytes ?? 0, 0)
        XCTAssertGreaterThan(capacity.totalBytes ?? 0, 0)
    }

    func testDiskCapacityReadFromMissingPathIsUnavailable() {
        let missing = URL(fileURLWithPath: "/nonexistent-w1-devicekit-volume")
        let capacity = DiskCapacity.read(volumeURL: missing)
        XCTAssertNil(capacity.opportunisticBytes)
        XCTAssertNil(capacity.importantBytes)
        XCTAssertNil(capacity.totalBytes)
        XCTAssertNotNil(capacity.unavailableReason)
        XCTAssertFalse(capacity.unavailableReason?.isEmpty ?? true)
    }

    // MARK: - Report assembly

    func testReportAssembly() {
        let measuredAt = Date(timeIntervalSince1970: 2_000_000)
        let metrics = DeviceScreenMetrics.from(
            identifier: "iPhone18,4",
            points: CGSize(width: 420, height: 912),
            pixels: CGSize(width: 1260, height: 2736),
            scale: 3.0, nativeScale: 3.0)
        let report = DeviceDiagnosticsReport(
            screenMetrics: metrics,
            biometrics: BiometricStatus(kind: .faceID, canEvaluate: true, detail: nil),
            isLowPowerModeEnabled: false,
            brightness: ScreenBrightness.from(0.75),
            diskCapacity: DiskCapacity.from(opportunistic: 10, important: 20, total: 30),
            measuredAt: measuredAt)
        XCTAssertEqual(report.screenMetrics.modelName, "iPhone Air")
        XCTAssertEqual(report.biometrics.kind, .faceID)
        XCTAssertFalse(report.isLowPowerModeEnabled)
        XCTAssertEqual(report.brightness.percent, 75)
        XCTAssertEqual(report.diskCapacity.totalBytes, 30)
        XCTAssertEqual(report.measuredAt, measuredAt)
        XCTAssertEqual(report, report)
    }

    // MARK: - W1 registration

    func testRegistrationHasFiveItems() {
        XCTAssertEqual(W1DeviceDiagnosticsRegistration.items.count, 5)
        XCTAssertEqual(W1DeviceDiagnosticsRegistration.allIDs.count, 5)
    }

    func testRegistrationItemsAreWellFormed() {
        let expectedSections: Set<String> = ["screen", "biometrics", "lowPower", "brightness", "disk"]
        var sections: Set<String> = []
        var chineseTitles: Set<String> = []
        for item in W1DeviceDiagnosticsRegistration.items {
            XCTAssertTrue(item.id.hasPrefix("w1."), item.id)
            XCTAssertFalse(item.chineseTitle.isEmpty, item.id)
            XCTAssertFalse(item.englishTitle.isEmpty, item.id)
            XCTAssertFalse(item.description.isEmpty, item.id)
            XCTAssertEqual(item.category, .deviceDiagnostics, item.id)
            XCTAssertEqual(item.viewType, "DeviceDiagnosticsCard", item.id)
            XCTAssertEqual(item.viewType, W1DeviceDiagnosticsRegistration.viewType, item.id)
            sections.insert(item.section)
            chineseTitles.insert(item.chineseTitle)
        }
        XCTAssertEqual(sections, expectedSections)
        XCTAssertEqual(chineseTitles.count, 5, "Chinese titles must be distinct")
    }

    func testRegistrationChineseTitles() {
        let titles = W1DeviceDiagnosticsRegistration.items.map(\.chineseTitle)
        XCTAssertTrue(titles.contains("屏幕物理指标"))
        XCTAssertTrue(titles.contains("生物识别硬件"))
        XCTAssertTrue(titles.contains("低电量模式"))
        XCTAssertTrue(titles.contains("屏幕亮度"))
        XCTAssertTrue(titles.contains("可用磁盘容量"))
    }
}
