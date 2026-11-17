import Foundation
import SQLite3
import XCTest
@testable import GestaltX

/// Offline tests for the battery telemetry queries (A7, Erosion-CN
/// PowerTelemetryView): the battery and thermal SQL queries run
/// against a fixture powerlog database built in the test, so the
/// column mapping, temperature normalisation, health computation
/// and thermal-level summaries are verified without a device.
final class PowerTelemetryTests: XCTestCase {
    private var db: OpaquePointer?

    override func setUpWithError() throws {
        try super.setUpWithError()
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(":memory:", &handle), SQLITE_OK)
        db = handle
        let schema = """
        CREATE TABLE PLBatteryAgent_EventBackward_Battery (
            timestamp REAL, Level REAL, AppleRawMaxCapacity INTEGER,
            NominalChargeCapacity INTEGER, DesignCapacity INTEGER,
            CycleCount INTEGER, Voltage INTEGER, InstantAmperage INTEGER,
            Temperature REAL, IsCharging INTEGER);
        CREATE TABLE PLThermalAgent_EventPoint_ThermalStatus (
            timestamp REAL, ThermalLevel INTEGER);
        INSERT INTO PLBatteryAgent_EventBackward_Battery VALUES
            (1700000000, 80, 3200, 3300, 3400, 123, 3900, 500, 28.5, 1),
            (1700000600, 81, 3200, 3300, 3400, 123, 3900, -200, 2850, 0);
        INSERT INTO PLThermalAgent_EventPoint_ThermalStatus VALUES
            (1700000000, 0), (1700000600, 15), (1700001200, 25);
        """
        var error: UnsafeMutablePointer<CChar>?
        let execResult = sqlite3_exec(db, schema, nil, nil, &error)
        if execResult != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "unknown error"
            XCTFail("fixture schema failed: \(message)")
        }
        XCTAssertEqual(execResult, SQLITE_OK)
    }

    override func tearDownWithError() throws {
        if let db { sqlite3_close(db) }
        db = nil
        try super.tearDownWithError()
    }

    func testBatterySamplesAreNewestFirst() throws {
        let samples = PowerTelemetry.queryBatterySamples(db: try XCTUnwrap(db))
        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples[0].timestamp.timeIntervalSince1970, 1700000600, accuracy: 0.001)
        XCTAssertEqual(samples[1].timestamp.timeIntervalSince1970, 1700000000, accuracy: 0.001)
    }

    func testBatterySampleFields() throws {
        let samples = PowerTelemetry.queryBatterySamples(db: try XCTUnwrap(db))
        let latest = try XCTUnwrap(samples.first)
        XCTAssertEqual(latest.levelPercent, 81)
        XCTAssertEqual(latest.rawMaxCapacitymAh, 3200)
        XCTAssertEqual(latest.nominalCapacitymAh, 3300)
        XCTAssertEqual(latest.designCapacitymAh, 3400)
        XCTAssertEqual(latest.cycleCount, 123)
        XCTAssertEqual(latest.voltagemV, 3900)
        XCTAssertEqual(latest.amperagemA, -200)
        XCTAssertEqual(latest.isCharging, false)
    }

    func testTemperatureHundredthsAreNormalised() throws {
        // The second row stores 2850 (hundredths of a degree); it
        // must read as 28.5 °C, not 2850 °C.
        let samples = PowerTelemetry.queryBatterySamples(db: try XCTUnwrap(db))
        XCTAssertEqual(samples[0].temperatureCelsius, 28.5, accuracy: 0.001)
        XCTAssertEqual(samples[1].temperatureCelsius, 28.5, accuracy: 0.001)
    }

    func testTrueHealthPercent() throws {
        let samples = PowerTelemetry.queryBatterySamples(db: try XCTUnwrap(db))
        let latest = try XCTUnwrap(samples.first)
        XCTAssertEqual(latest.trueHealthPercent ?? 0, 3200.0 / 3400.0 * 100.0, accuracy: 0.001)
    }

    func testComputedPowerWatts() throws {
        let samples = PowerTelemetry.queryBatterySamples(db: try XCTUnwrap(db))
        let latest = try XCTUnwrap(samples.first)
        XCTAssertEqual(latest.computedPowerWatts ?? 0, 3900.0 * -200.0 / 1_000_000.0, accuracy: 0.0001)
    }

    func testHealthIsNilWithoutDesignCapacity() {
        let sample = BatteryTelemetrySample(id: UUID(), timestamp: Date(), levelPercent: 50,
                                            rawMaxCapacitymAh: 3000, nominalCapacitymAh: nil,
                                            designCapacitymAh: nil, cycleCount: nil,
                                            voltagemV: nil, amperagemA: nil,
                                            temperatureCelsius: nil, isCharging: nil)
        XCTAssertNil(sample.trueHealthPercent)
        XCTAssertNil(sample.computedPowerWatts)
    }

    func testThermalEventsAreNewestFirst() throws {
        let events = PowerTelemetry.queryThermalEvents(db: try XCTUnwrap(db))
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0].levelCode, 25)
        XCTAssertEqual(events[1].levelCode, 15)
        XCTAssertEqual(events[2].levelCode, 0)
    }

    func testThermalSummaries() throws {
        let events = PowerTelemetry.queryThermalEvents(db: try XCTUnwrap(db))
        XCTAssertTrue(events[0].summary.contains("Heavy"))
        XCTAssertTrue(events[1].summary.contains("Moderate"))
        XCTAssertTrue(events[2].summary.contains("Nominal"))
    }

    func testEmptyDatabaseReturnsNoSamples() throws {
        var empty: OpaquePointer?
        XCTAssertEqual(sqlite3_open(":memory:", &empty), SQLITE_OK)
        defer { if let empty { sqlite3_close(empty) } }
        XCTAssertTrue(PowerTelemetry.queryBatterySamples(db: try XCTUnwrap(empty)).isEmpty)
        XCTAssertTrue(PowerTelemetry.queryThermalEvents(db: try XCTUnwrap(empty)).isEmpty)
    }
}
