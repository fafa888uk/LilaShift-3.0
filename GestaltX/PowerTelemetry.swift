// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import SQLite3

/// Read-only hardware battery health and SoC thermal telemetry (A7).
/// The mechanism is Erosion-CN's `PowerTelemetryView` (Kianuni,
/// GPL-3.0), reimplemented for LilaShift's access helper and snapshot
/// reader: `CurrentPowerlog.PLSQL` is cloned with APFS `clonefile()`
/// into a private temporary directory and parsed read-only, so the
/// live database is never locked and `powerlogHelperd` is never
/// blocked. This is strictly read-only — no battery key is ever
/// written, and the existing `UIDevice` battery display (level and
/// state) is untouched. Battery health, cycle count and capacity are
/// not available through public iOS APIs; this reads the hardware
/// powerlog the system itself maintains, which is why it needs the
/// container access grant. When the firmware does not grant the
/// powerlog token the reader reports `.unavailable` instead of
/// inventing numbers.
struct BatteryTelemetrySample: Identifiable, Equatable, Codable {
    let id: UUID
    let timestamp: Date
    let levelPercent: Double?
    let rawMaxCapacitymAh: Int?
    let nominalCapacitymAh: Int?
    let designCapacitymAh: Int?
    let cycleCount: Int?
    let voltagemV: Int?
    let amperagemA: Int?
    let temperatureCelsius: Double?
    let isCharging: Bool?

    var computedPowerWatts: Double? {
        guard let v = voltagemV, let a = amperagemA else { return nil }
        return (Double(v) * Double(a)) / 1_000_000.0
    }

    var trueHealthPercent: Double? {
        guard let raw = rawMaxCapacitymAh, let design = designCapacitymAh, design > 0 else { return nil }
        return (Double(raw) / Double(design)) * 100.0
    }
}

struct ThermalTelemetryEvent: Identifiable, Equatable, Codable {
    let id: UUID
    let timestamp: Date
    let levelCode: Int
    let summary: String
}

enum PowerTelemetry {
    static let powerlogDirectory =
        "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.powerlog/Library/BatteryLife"
    static let powerlogDatabasePath =
        "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.powerlog/Library/BatteryLife/CurrentPowerlog.PLSQL"

    /// The result of a read: whether the database could be opened,
    /// the newest battery samples (newest first), and thermal events.
    struct ReadResult {
        let accessible: Bool
        let batterySamples: [BatteryTelemetrySample]
        let thermalEvents: [ThermalTelemetryEvent]
        let message: String?
    }

    /// Reads the powerlog snapshot. Grants read-only container access
    /// first; returns `accessible: false` when the firmware does not
    /// grant the powerlog token.
    static func read() -> ReadResult {
        let fm = FileManager.default
        let wasActive = ContainerAccess.hasActiveAccess(path: powerlogDirectory)
        let grant = ContainerAccess.grantAccess(path: powerlogDirectory, requireWrite: false)
        defer {
            if !wasActive {
                ContainerAccess.releaseAccess(path: powerlogDirectory)
            }
        }
        guard grant.granted, fm.isReadableFile(atPath: powerlogDatabasePath) else {
            return ReadResult(accessible: false, batterySamples: [], thermalEvents: [],
                              message: grant.error ?? L("The powerlog container could not be opened on this firmware."))
        }
        do {
            let parsed = try SQLiteSnapshotHelper.withClonedDatabase(at: powerlogDatabasePath) { db in
                (queryBatterySamples(db: db), queryThermalEvents(db: db))
            }
            return ReadResult(accessible: true, batterySamples: parsed.0, thermalEvents: parsed.1, message: nil)
        } catch {
            return ReadResult(accessible: false, batterySamples: [], thermalEvents: [],
                              message: error.localizedDescription)
        }
    }

    /// Battery samples from the `PLBatteryAgent` tables, newest first
    /// (at most 25). Pure over an open SQLite handle, so tests can
    /// build a fixture database and verify the mapping.
    static func queryBatterySamples(db: OpaquePointer) -> [BatteryTelemetrySample] {
        let tables = SQLiteSnapshotHelper.allTables(in: db)
        let candidates = [
            "PLBatteryAgent_EventBackward_Battery",
            "PLBatteryAgent_EventForward_Battery",
            "PLBatteryAgent_EventBackward_BatteryUI",
        ]
        guard let tableName = candidates.first(where: { tables.contains($0) })
                ?? tables.first(where: { $0.contains("PLBatteryAgent") && $0.hasSuffix("_Battery") }) else {
            return []
        }
        let cols = SQLiteSnapshotHelper.columnNames(in: tableName, db: db)
        guard cols.contains("timestamp") else { return [] }

        func pick(_ names: [String]) -> String {
            for name in names where cols.contains(name) {
                return "\"\(name)\""
            }
            return "NULL"
        }

        let sql = """
        SELECT timestamp,
               \(pick(["Level", "CurrentCapacity"])),
               \(pick(["AppleRawMaxCapacity", "RawMaxCapacity", "MaxCapacity"])),
               \(pick(["NominalChargeCapacity", "MaxCapacity"])),
               \(pick(["DesignCapacity"])),
               \(pick(["CycleCount"])),
               \(pick(["Voltage"])),
               \(pick(["InstantAmperage", "Amperage"])),
               \(pick(["Temperature"])),
               \(pick(["IsCharging"]))
        FROM "\(tableName)"
        ORDER BY timestamp DESC
        LIMIT 25;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let validStmt = stmt else {
            return []
        }
        defer { sqlite3_finalize(validStmt) }

        var samples: [BatteryTelemetrySample] = []
        while sqlite3_step(validStmt) == SQLITE_ROW {
            guard let ts = SQLiteSnapshotHelper.doubleCol(validStmt, 0) else { continue }
            let rawTemp = SQLiteSnapshotHelper.doubleCol(validStmt, 8)
            // Some firmwares store temperature in hundredths of a degree.
            let normalizedTemp: Double? = rawTemp.map { abs($0) > 120.0 ? ($0 / 100.0) : $0 }
            let chargingInt = SQLiteSnapshotHelper.intCol(validStmt, 9)
            samples.append(BatteryTelemetrySample(
                id: UUID(),
                timestamp: Date(timeIntervalSince1970: ts),
                levelPercent: SQLiteSnapshotHelper.doubleCol(validStmt, 1),
                rawMaxCapacitymAh: SQLiteSnapshotHelper.intCol(validStmt, 2),
                nominalCapacitymAh: SQLiteSnapshotHelper.intCol(validStmt, 3),
                designCapacitymAh: SQLiteSnapshotHelper.intCol(validStmt, 4),
                cycleCount: SQLiteSnapshotHelper.intCol(validStmt, 5),
                voltagemV: SQLiteSnapshotHelper.intCol(validStmt, 6),
                amperagemA: SQLiteSnapshotHelper.intCol(validStmt, 7),
                temperatureCelsius: normalizedTemp,
                isCharging: chargingInt.map { $0 != 0 }))
        }
        return samples
    }

    /// Thermal/ throttling events, newest first (at most 20).
    static func queryThermalEvents(db: OpaquePointer) -> [ThermalTelemetryEvent] {
        let tables = SQLiteSnapshotHelper.allTables(in: db)
        let candidates = [
            "PLThermalAgent_EventPoint_ThermalStatus",
            "PLXPCAgent_EventPoint_ThermalLevel",
            "PLThermalMonitorAgent_EventPoint_ThermalLevel",
        ]
        guard let tableName = candidates.first(where: { tables.contains($0) })
                ?? tables.first(where: { $0.localizedCaseInsensitiveContains("Thermal") && $0.contains("Event") }) else {
            return []
        }
        let cols = SQLiteSnapshotHelper.columnNames(in: tableName, db: db)
        guard cols.contains("timestamp") else { return [] }
        let levelCol = ["ThermalLevel", "thermalLevel", "Level", "State"].first(where: { cols.contains($0) })
        guard let levelCol else { return [] }

        let sql = "SELECT timestamp, \"\(levelCol)\" FROM \"\(tableName)\" ORDER BY timestamp DESC LIMIT 20;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let validStmt = stmt else {
            return []
        }
        defer { sqlite3_finalize(validStmt) }

        var events: [ThermalTelemetryEvent] = []
        while sqlite3_step(validStmt) == SQLITE_ROW {
            guard let ts = SQLiteSnapshotHelper.doubleCol(validStmt, 0),
                  let level = SQLiteSnapshotHelper.intCol(validStmt, 1) else { continue }
            let summary: String
            switch level {
            case ..<1: summary = L("Thermal recovered to normal (Nominal)")
            case 1...10: summary = L("Light thermal intervention (Light / Fair)")
            case 11...20: summary = L("Moderate throttling and frame limiting (Moderate / Serious)")
            case 21...30: summary = L("Heavy performance restriction and dimming (Heavy)")
            default: summary = L("Overheat protection threshold triggered (Critical)")
            }
            events.append(ThermalTelemetryEvent(id: UUID(), timestamp: Date(timeIntervalSince1970: ts),
                                                levelCode: level, summary: summary))
        }
        return events
    }
}
