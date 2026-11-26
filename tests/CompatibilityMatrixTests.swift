import Foundation
import XCTest
@testable import GestaltX

/// Compatibility matrix tests (A23, `docs/COMPATIBILITY_ZH-CN.md`):
/// structural invariants — every system row has one cell per iOS
/// column, every cell and row cites its source, and the documented
/// support facts (iOS 27 on-device access, iOS 26 unsupported,
/// eSIM needs hardware, never change ProductType) are encoded.
final class CompatibilityMatrixTests: XCTestCase {
    func testSystemRowsHaveOneCellPerColumn() {
        XCTAssertFalse(CompatibilityMatrix.systemRows.isEmpty)
        for row in CompatibilityMatrix.systemRows {
            XCTAssertEqual(row.cells.count, CompatibilityMatrix.iosColumns.count,
                           "Row \(row.feature) must have one cell per iOS column")
            XCTAssertFalse(row.source.isEmpty)
        }
    }

    func testOnDeviceAccessBySystemVersion() {
        let row = CompatibilityMatrix.systemRows.first { $0.feature == "On-device MobileGestalt access" }
        XCTAssertNotNil(row)
        XCTAssertEqual(row!.cells[0].status, .supported)
        XCTAssertEqual(row!.cells[1].status, .unsupported)
        XCTAssertEqual(row!.cells[2].status, .unsupported)
    }

    func testLocalPlistEditingBySystemVersion() {
        let row = CompatibilityMatrix.systemRows.first { $0.feature == "Local plist editing" }
        XCTAssertNotNil(row)
        XCTAssertEqual(row!.cells[0].status, .supported)
        XCTAssertEqual(row!.cells[1].status, .supported)
        XCTAssertEqual(row!.cells[2].status, .unverified)
    }

    func testAIStagingIsConditionalOnIOS27() {
        let row = CompatibilityMatrix.systemRows.first { $0.feature == "Apple Intelligence staging" }
        XCTAssertNotNil(row)
        XCTAssertEqual(row!.cells[0].status, .conditional)
        XCTAssertTrue(row!.cells[0].note.contains("four conditions"))
    }

    func testDeviceRowsCiteSources() {
        XCTAssertFalse(CompatibilityMatrix.deviceRows.isEmpty)
        for row in CompatibilityMatrix.deviceRows {
            XCTAssertFalse(row.source.isEmpty, "Device row \(row.device) / \(row.feature) has no source")
            XCTAssertFalse(row.note.isEmpty)
        }
    }

    func testESIMNeedsHardware() {
        let noEUICC = CompatibilityMatrix.deviceRows.first {
            $0.device.contains("no eUICC") && $0.feature == "Add eSIM"
        }
        XCTAssertEqual(noEUICC?.status, .unsupported)
        let proMax = CompatibilityMatrix.deviceRows.first {
            $0.device.contains("18 Pro") && $0.feature == "Add eSIM"
        }
        XCTAssertEqual(proMax?.status, .conditional)
    }

    func testProductTypeChangeIsNeverSupported() {
        let row = CompatibilityMatrix.deviceRows.first { $0.feature == "Change ProductType" }
        XCTAssertEqual(row?.status, .unsupported)
    }

    func testInstallRows() {
        XCTAssertEqual(CompatibilityMatrix.installRows.count, 3)
        XCTAssertTrue(CompatibilityMatrix.installRows.contains { $0.method == "LiveContainer" })
        XCTAssertTrue(CompatibilityMatrix.installRows.contains { $0.method.contains("AltStore") })
        XCTAssertTrue(CompatibilityMatrix.installRows.contains { $0.method.contains("Paid developer") })
    }

    func testDisclaimerStatesTheVerificationLimit() {
        XCTAssertTrue(CompatibilityMatrix.verificationDisclaimer.contains("not verified device-by-device"))
    }
}
