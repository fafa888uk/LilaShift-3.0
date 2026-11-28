// SPDX-License-Identifier: GPL-3.0-only
// Structured log (LilaShift 5.0.0, Wave 1 W2) — the "structured
// log + export" display idea from kean/Pulse, reimplemented on
// LilaShift's own log sources only. No Pulse dependency, no Pulse
// code: Pulse's core value is recording the app's own URLSession
// traffic, and LilaShift makes almost no network requests of its
// own, so there is nothing to record there. This file therefore
// records no network requests and shows none: it only structures
// what LilaShift already logs — the structured operation events
// recorded by `OperationEventRecorder` (read/backup outcomes this
// session) and the free-text session log lines
// (`GestaltManager.logs`).
//
// Honesty rules, enforced by the types:
//   • Every entry carries its real source (`.operationEvent` or
//     `.sessionLine`). A session line has no recorded time, so its
//     `date` is `nil` — never a made-up timestamp.
//   • Write, restore and guard events are still not recorded (see
//     `OperationLogSnapshot.writeAndRestoreEventsConnected`); the
//     export says so instead of presenting the log as complete.
//   • Details are passed through `LilaLog.redact` at entry
//     construction and again at export (redaction is idempotent),
//     so no device identifier can leak into a shared file.
import Foundation

/// Log severity for structured log entries. Derived from the
/// operation event kind (see `level(for:)`): failures are errors,
/// guards and unresolved slots are warnings, successes are info.
/// Session log lines are always info: a free-text line carries no
/// severity of its own, and guessing one would be invented data.
enum StructuredLogLevel: String, CaseIterable, Codable, Sendable {
    case info
    case warning
    case error

    var title: String {
        switch self {
        case .info: return L("Info")
        case .warning: return L("Warning")
        case .error: return L("Error")
        }
    }

    /// The level for one operation event kind. Exhaustive over all
    /// thirteen kinds, so a future kind cannot silently fall
    /// through to a default.
    static func level(for kind: OperationEventKind) -> StructuredLogLevel {
        switch kind {
        case .readFailed, .writeFailed, .restoreFailed, .backupFailed:
            return .error
        case .guardLayoutUnresolved, .guardHardwareIdentity, .guardNativeConflict,
             .slotUnresolvable, .regionReverted:
            return .warning
        case .readSucceeded, .writeVerified, .restoreSucceeded, .backupCreated:
            return .info
        }
    }
}

/// Where a structured log entry came from. The two sources are
/// kept apart because they have different guarantees: an operation
/// event has a recorded time and kind, a session line has neither.
enum StructuredLogSource: String, CaseIterable, Codable, Sendable {
    case operationEvent
    case sessionLine

    var title: String {
        switch self {
        case .operationEvent: return L("Operation event")
        case .sessionLine: return L("Session log")
        }
    }
}

/// One structured log entry: a single operation event or a single
/// free-text session log line, with a level, a source and a
/// redacted detail. All fields are `Codable`, so an entry round
/// trips through the JSON export unchanged.
struct StructuredLogEntry: Equatable, Identifiable, Codable, Sendable {
    let id: UUID
    /// The recorded time, or `nil` for a session line: free-text
    /// lines carry no timestamp, and none is invented for them.
    let date: Date?
    let level: StructuredLogLevel
    let source: StructuredLogSource
    /// The operation kind, or `nil` for a session line.
    let kind: OperationEventKind?
    /// The affected key or slot, when the event is about one.
    let key: String?
    /// The feature this entry belongs to, when known.
    let featureID: String?
    let title: String
    /// The observed fact, redacted (see `LilaLog.redact`).
    let detail: String

    /// Builds an entry from one structured operation event.
    init(event: OperationEvent) {
        id = UUID()
        date = event.date
        level = StructuredLogLevel.level(for: event.kind)
        source = .operationEvent
        kind = event.kind
        key = event.key
        featureID = event.featureID
        title = event.kind.title
        detail = LilaLog.redact(event.detail)
    }

    /// Builds an entry from one free-text session log line. The
    /// line has no recorded time and no kind, so `date` is `nil`,
    /// `kind` is `nil` and the level is always info.
    init(sessionLine: String) {
        id = UUID()
        date = nil
        level = .info
        source = .sessionLine
        kind = nil
        key = nil
        featureID = nil
        title = L("Session log")
        detail = LilaLog.redact(sessionLine)
    }

    /// The text keyword search matches against: title, detail, key,
    /// feature id and kind (raw value and title).
    var searchableText: String {
        [title, detail, key ?? "", featureID ?? "", kind?.rawValue ?? "", kind?.title ?? ""]
            .joined(separator: " ")
    }

    /// Whether this entry matches a keyword. Case-insensitive; an
    /// empty keyword matches everything.
    func matches(keyword: String) -> Bool {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return searchableText.localizedCaseInsensitiveContains(trimmed)
    }
}

/// The viewer's filter: keyword search, level set, kind set,
/// source and an optional date range. An empty set (or a `nil`
/// bound) means "no restriction on that axis", never "match
/// nothing".
struct StructuredLogFilter: Equatable, Sendable {
    var keyword: String = ""
    var levels: Set<StructuredLogLevel> = []
    var kinds: Set<OperationEventKind> = []
    var source: StructuredLogSource? = nil
    var fromDate: Date? = nil
    var toDate: Date? = nil

    static let unfiltered = StructuredLogFilter()

    var isActive: Bool {
        !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !levels.isEmpty || !kinds.isEmpty || source != nil
            || fromDate != nil || toDate != nil
    }

    func matches(_ entry: StructuredLogEntry) -> Bool {
        if !entry.matches(keyword: keyword) { return false }
        if !levels.isEmpty && !levels.contains(entry.level) { return false }
        if !kinds.isEmpty {
            guard let kind = entry.kind, kinds.contains(kind) else { return false }
        }
        if let source, entry.source != source { return false }
        if fromDate != nil || toDate != nil {
            // An entry with no recorded time cannot be shown to
            // fall inside a date range, so it is excluded when a
            // range is set — it is not assigned a made-up date.
            guard let date = entry.date else { return false }
            if let fromDate, date < fromDate { return false }
            if let toDate, date > toDate { return false }
        }
        return true
    }

    func applying(to entries: [StructuredLogEntry]) -> [StructuredLogEntry] {
        entries.filter { matches($0) }
    }

    /// The inclusive calendar-day range containing `date`, for the
    /// "filter by date" picker: from the start of the day to the
    /// last second of the same day.
    static func dayRange(for date: Date, calendar: Calendar = .current) -> (from: Date, to: Date) {
        let from = calendar.startOfDay(for: date)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: from) ?? from
        return (from, nextDay.addingTimeInterval(-1))
    }
}

/// Structured-log assembly and summaries over one operation log
/// snapshot. Pure functions: they read the snapshot, write
/// nothing, and invent nothing.
enum StructuredLog {
    /// Every operation event kind, in declaration order, for the
    /// kind filter picker. Listed explicitly (the kind enum is not
    /// `CaseIterable`) so a future kind is a visible gap here, not
    /// a silently missing filter option.
    static let allKinds: [OperationEventKind] = [
        .readSucceeded, .readFailed,
        .writeVerified, .writeFailed,
        .restoreSucceeded, .restoreFailed,
        .guardLayoutUnresolved, .guardHardwareIdentity, .guardNativeConflict,
        .slotUnresolvable,
        .backupCreated, .backupFailed,
        .regionReverted,
    ]

    /// Builds the structured entries for one snapshot: structured
    /// events in the order supplied (newest first, as recorded),
    /// then the free-text session lines, newest first. The two
    /// groups are not interleaved: session lines have no timestamp,
    /// so no true chronological merge exists.
    static func entries(from snapshot: OperationLogSnapshot) -> [StructuredLogEntry] {
        let eventEntries = snapshot.events.map { StructuredLogEntry(event: $0) }
        let lineEntries = snapshot.freeTextLines.reversed().map { StructuredLogEntry(sessionLine: $0) }
        return eventEntries + lineEntries
    }

    /// The per-level counts for a set of entries. Every level is
    /// always present, even at zero.
    static func countsByLevel(_ entries: [StructuredLogEntry]) -> [StructuredLogLevel: Int] {
        var counts: [StructuredLogLevel: Int] = [.info: 0, .warning: 0, .error: 0]
        for entry in entries {
            counts[entry.level, default: 0] += 1
        }
        return counts
    }
}

// MARK: - Export

/// The two export formats. JSON keeps the full structure (level,
/// source, kind, key, feature id) for a bug report; text is a
/// plain readable log. Both go through the system share sheet via
/// `TemporaryExport`, exactly like the session log share.
enum StructuredLogExportFormat: String, CaseIterable, Sendable {
    case json
    case text

    var title: String {
        switch self {
        case .json: return L("JSON")
        case .text: return L("Text")
        }
    }

    var fileExtension: String {
        switch self {
        case .json: return "json"
        case .text: return "log"
        }
    }

    func fileName(exportedAt: Date = Date()) -> String {
        "LilaShift-operation-log-\(Int(exportedAt.timeIntervalSince1970)).\(fileExtension)"
    }
}

/// The JSON export document: the exported entries plus the
/// provenance a reader needs to interpret them — when it was
/// exported, how many entries it holds, and the explicit statement
/// that write/restore/guard events are not connected yet, so the
/// file is never mistaken for a complete record.
struct StructuredLogExportDocument: Codable, Equatable, Sendable {
    let formatVersion: Int
    let exportedAt: Date
    let entryCount: Int
    let writeAndRestoreEventsConnected: Bool
    let entries: [StructuredLogEntry]
}

/// Builds the shareable log export. Pure except for
/// `temporaryExport`, which writes one file under the temporary
/// directory (cleaned up by the share sheet, as in
/// `SessionLogView`). Every detail is redacted before it leaves
/// the app; redaction is idempotent, so re-redacting at export is
/// safe.
enum StructuredLogExporter {
    static let formatVersion = 1

    /// The JSON document for these entries. Throws only when
    /// encoding fails.
    static func jsonData(for entries: [StructuredLogEntry], exportedAt: Date = Date()) throws -> Data {
        let document = StructuredLogExportDocument(
            formatVersion: formatVersion,
            exportedAt: exportedAt,
            entryCount: entries.count,
            writeAndRestoreEventsConnected: OperationLogSnapshot.writeAndRestoreEventsConnected,
            entries: entries)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    /// The plain-text log for these entries: a header stating the
    /// source, the count and the coverage gap, then one line per
    /// entry. The header states explicitly that the log holds no
    /// network request records.
    static func text(for entries: [StructuredLogEntry], exportedAt: Date = Date()) -> String {
        var lines: [String] = []
        lines.append(L("LilaShift operation log"))
        lines.append(String(format: L("Exported at: %@"), iso8601String(exportedAt)))
        lines.append(String(format: L("%d entries"), entries.count))
        lines.append(OperationLogSnapshot.writeAndRestoreNote)
        lines.append(L("This log contains only this app's own operation events and session log lines. It contains no network request records: LilaShift makes almost no network requests of its own."))
        lines.append("")
        for entry in entries {
            lines.append(textLine(for: entry))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// One text-export line: `[time] [LEVEL] title — detail`.
    /// Undated entries (session lines) show "unknown time".
    static func textLine(for entry: StructuredLogEntry) -> String {
        let time = entry.date.map { iso8601String($0) } ?? L("unknown time")
        return "[\(time)] [\(entry.level.rawValue.uppercased())] \(entry.title) — \(LilaLog.redact(entry.detail))"
    }

    /// The export data for these entries in the requested format.
    static func data(for entries: [StructuredLogEntry], format: StructuredLogExportFormat, exportedAt: Date = Date()) throws -> Data {
        switch format {
        case .json: return try jsonData(for: entries, exportedAt: exportedAt)
        case .text: return Data(text(for: entries, exportedAt: exportedAt).utf8)
        }
    }

    /// A shareable temporary file for these entries, for the system
    /// share sheet. The caller presents it with `ShareSheet` and
    /// the sheet cleans it up afterwards.
    static func temporaryExport(for entries: [StructuredLogEntry], format: StructuredLogExportFormat, exportedAt: Date = Date()) throws -> TemporaryExport {
        try TemporaryExport(
            data: try data(for: entries, format: format, exportedAt: exportedAt),
            name: format.fileName(exportedAt: exportedAt))
    }

    static func iso8601String(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
