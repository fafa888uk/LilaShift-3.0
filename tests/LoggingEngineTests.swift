// SPDX-License-Identifier: GPL-3.0-only
// LoggingEngine tests (Stage 3, ADR-2-06).
//
// The fixtures use made-up identifiers, never a real device's: the
// UDID and serial below are invented for the test.
import Foundation
import XCTest
@testable import GestaltX

final class LoggingEngineTests: XCTestCase {
    func testRedactsIdentifierValues() {
        XCTAssertEqual(
            LilaLog.redact("UniqueDeviceID=00008150-000C0C5A14D2401C"),
            "UniqueDeviceID=[redacted]",
            "A UDID after its key is masked")
        XCTAssertEqual(
            LilaLog.redact("SerialNumber: DLXQ12345678"),
            "SerialNumber=[redacted]",
            "A serial after its key is masked in the colon form too")
        XCTAssertEqual(
            LilaLog.redact("re6Zb+zwFKJNlkQTUeT+/w=00008150-000C0C5A14D2401C"),
            "re6Zb+zwFKJNlkQTUeT+/w=[redacted]",
            "A UDID after its MobileGestalt question hash is masked")
        XCTAssertEqual(
            LilaLog.redact("UniqueChipID=123456789012345"),
            "UniqueChipID=[redacted]",
            "A chip ID after its key is masked")
    }

    func testRedactsStandaloneHexIdentifiers() {
        XCTAssertEqual(
            LilaLog.redact("device 00008150000c0c5a14d2401c00008150000c0c5a logged in"),
            "device [redacted] logged in",
            "A standalone 40-hex UDID is masked")
        XCTAssertEqual(
            LilaLog.redact("serial ab12cd34ef56 found"),
            "serial [redacted] found",
            "A standalone 12-hex serial is masked")
        XCTAssertEqual(
            LilaLog.redact("device 00008150-000C0C5A14D2401C connected"),
            "device [redacted] connected",
            "A dashed UDID is masked")
    }

    func testLeavesOrdinaryText() {
        let text = "region LL, model iPhone18,1 (A3518), key A62OafQ85EJAiiqKn4agtg staged"
        XCTAssertEqual(LilaLog.redact(text), text,
                       "Region codes, model numbers and MobileGestalt keys are not device identifiers")
    }

    func testRedactIsIdempotent() {
        let text = "UniqueDeviceID=00008150-000C0C5A14D2401C and serial ab12cd34ef56"
        XCTAssertEqual(LilaLog.redact(LilaLog.redact(text)), LilaLog.redact(text),
                       "Redacting twice changes nothing")
    }

    func testSubsystemIsTheAppBundle() {
        XCTAssertEqual(LilaLog.subsystem, "com.huami.gestultx",
                       "Logs land under the app's bundle identifier")
    }
}
