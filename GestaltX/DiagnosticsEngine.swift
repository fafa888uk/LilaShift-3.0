// SPDX-License-Identifier: GPL-3.0-only
// Diagnostics engine (Stage 6, ADR-2-09 / DATA_MODELS §3): the
// unified diagnostics input/output model.
//
// The ten scattered diagnostics files (HomeDiagnosticsCache,
// SmartFaultDiagnosis, DiagnosticsExpansion, SystemHealthScore,
// DependencyAnalyzer, CrashDiagnostics, PowerTelemetry,
// SupervisionAudit, AIReadinessCheckup, PostModificationAcceptance)
// converge here on one I/O model: `DiagnosticsInput` (value
// snapshots only) -> `DiagnosticsReport` (findings + the six repair
// suggestions + evidence). The engine itself is pure: no file I/O,
// no live objects, no writes, no timers. It consumes the other
// modules' outputs (MGMonitor rows, RestoreEngine reports, backup
// verifications, fingerprint comparisons, operation events) instead
// of re-implementing them; SmartFaultDiagnosis and the rest stay as
// the suppliers of those inputs.
//
// Honesty rules, enforced by the types:
//   • A finding is either observed or not — the engine never invents
//     a cause. When the cause is not known the fix is
//     `.cannotConfirm`, never a guessed cause.
//   • A suggested fix is a suggestion, never a guarantee: the report
//     carries the disclaimer on every display, and no suggestion
//     executes itself — nothing in this file modifies device data.
//   • Evidence is quoted from the inputs and passed through
//     `LilaLog.redact` at construction, so a report never leaks a
//     UDID, serial number or chip ID.
//   • Unknown stays unknown: a value that could not be read is
//     reported as unreadable, never as a difference and never as
//     "no data".
//
// Task-book §5.2's worked example ("Apple Intelligence enabled but
// not working") is the first end-to-end use case: the AI rule walks
// the chain hardware -> system version -> field values -> write
// success -> re-read -> cold restart -> dependencies, one finding
// per failed check. The system-version check lives in the sentinel
// rule (one owner, no duplicates); the AI rule cross-references it.
//
// Deviation from DATA_MODELS §3.1, recorded: the design sketched the
// device input as a `DeviceSnapshot` type. The codebase already has
// that snapshot — `DeviceProfile` — so the input takes a small
// `DiagnosticsDevice` converted from a profile (unknown
// ProfileValues become nil), not a second device-snapshot type.
import Foundation

// MARK: - Input: device snapshot

/// The device facts the rules need, as plain values. Built from a
/// `DeviceProfile` (unknown values become nil) or directly in tests.
/// No identifiers beyond product/model strings: a UDID, serial
/// number or chip ID never enters a diagnostics input.
struct DiagnosticsDevice: Equatable, Sendable {
    let productType: String?
    let modelNumber: String?
    let osVersion: String?
    let osBuild: String?
    let regionCode: String?
    let isNativeAppleIntelligence: Bool?

    init(productType: String? = nil,
         modelNumber: String? = nil,
         osVersion: String? = nil,
         osBuild: String? = nil,
         regionCode: String? = nil,
         isNativeAppleIntelligence: Bool? = nil) {
        self.productType = productType
        self.modelNumber = modelNumber
        self.osVersion = osVersion
        self.osBuild = osBuild
        self.regionCode = regionCode
        self.isNativeAppleIntelligence = isNativeAppleIntelligence
    }

    init(profile: DeviceProfile) {
        self.init(productType: profile.productType.value,
                  modelNumber: profile.modelNumber.value,
                  osVersion: profile.osVersion.value,
                  osBuild: profile.osBuild.value,
                  regionCode: profile.regionCode.value,
                  isNativeAppleIntelligence: profile.isNativeAppleIntelligence.value)
    }
}

/// The MG read state, as observed — never a guessed value.
enum MGReadState: Equatable, Sendable {
    /// Live values were read, with the read time.
    case live(values: [String: MGValue], readAt: Date)
    /// The read failed; the reason is quoted from the failure.
    case readFailed(reason: String)
    /// No read has happened yet.
    case notReadYet
}

/// Everything the diagnosis engine reads. Every field is a value
/// snapshot: the engine never touches the device, the file system or
/// a live manager. Optional or empty by default — the engine
/// diagnoses from whatever evidence the caller could supply, and
/// reports "no issues found" when the supplied evidence shows none.
struct DiagnosticsInput: Sendable {
    /// The device, or `nil` when it has never been read.
    let device: DiagnosticsDevice?
    let mgReadState: MGReadState
    /// First-read values by MG key (from the snapshot document).
    /// Empty when no document was read — the read state itself lives
    /// in `mgReadState`, so this map is never an optional collection.
    let snapshotValues: [String: MGValue]
    /// Staged values by MG key (from the working document).
    let workingValues: [String: MGValue]
    /// Backup records (metadata only — never payloads).
    let backups: [BackupRecord]
    /// Read-only verification results for the backup inventory.
    let backupVerifications: [BackupVerification]
    /// Stage 4 monitor rows (three sources per key).
    let monitorRows: [MGMonitorRow]
    /// Stage 5 restore-pipeline reports (eight steps each).
    let restoreReports: [RestoreEngine.Report]
    /// Structured operation events, when the caller records them.
    let events: [OperationEvent]
    /// The stored-vs-current fingerprint comparison, when a stored
    /// fingerprint exists.
    let fingerprintComparison: FingerprintComparison?
    /// Feature ids applied but not yet verified after a restart.
    let pendingRestartFeatureIDs: Set<String>

    init(device: DiagnosticsDevice? = nil,
         mgReadState: MGReadState = .notReadYet,
         snapshotValues: [String: MGValue] = [:],
         workingValues: [String: MGValue] = [:],
         backups: [BackupRecord] = [],
         backupVerifications: [BackupVerification] = [],
         monitorRows: [MGMonitorRow] = [],
         restoreReports: [RestoreEngine.Report] = [],
         events: [OperationEvent] = [],
         fingerprintComparison: FingerprintComparison? = nil,
         pendingRestartFeatureIDs: Set<String> = []) {
        self.device = device
        self.mgReadState = mgReadState
        self.snapshotValues = snapshotValues
        self.workingValues = workingValues
        self.backups = backups
        self.backupVerifications = backupVerifications
        self.monitorRows = monitorRows
        self.restoreReports = restoreReports
        self.events = events
        self.fingerprintComparison = fingerprintComparison
        self.pendingRestartFeatureIDs = pendingRestartFeatureIDs
    }

    /// The database keys' values in a document, keyed by MG key.
    /// Mirrors `GestaltManager.value(of:in:)` (a plaintext key is
    /// staged under its readable name, so the lookup retries with
    /// it). Keys absent from the document are absent here, never
    /// defaulted.
    static func values(in document: GestaltDocument?) -> [String: MGValue] {
        guard let document else { return [:] }
        var result: [String: MGValue] = [:]
        for record in MGDatabase.all {
            let raw = document.extra[record.obfuscatedName]
                ?? (record.readableName != record.obfuscatedName
                    ? document.extra[record.readableName] : nil)
            if let value = raw.flatMap(MGValue.fromPlistValue) {
                result[record.obfuscatedName] = value
            }
        }
        return result
    }
}

// MARK: - Output: findings and report

/// What a finding is about. Matches DATA_MODELS §3.2.
enum FindingCategory: String, Equatable, Sendable {
    case device
    case mgRead
    case mgWrite
    case backup
    case restore
    case compatibility
    case conflict
    case anomaly
}

/// How urgent a finding is. `.error` means a failure was observed;
/// `.warning` means a change did not take effect or needs attention;
/// `.info` means something is missing or unconfirmed, not broken.
enum Severity: String, Equatable, Sendable {
    case info
    case warning
    case error

    var sortOrder: Int {
        switch self {
        case .error: return 0
        case .warning: return 1
        case .info: return 2
        }
    }
}

/// The six repair-suggestion kinds (task-book §5.3). A suggestion
/// names an action; it never executes one, and it never claims the
/// action will work.
enum FixSuggestion: Equatable, Sendable {
    /// The app can fix this itself (for example re-reading).
    case autoFixable(action: String)
    /// The user must confirm before the app acts.
    case needsConfirmation(action: String)
    /// A fresh backup is needed before acting.
    case needsRebackup(action: String)
    /// A device restart (cold start) is needed.
    case needsColdRestart(action: String)
    /// The current system does not support this.
    case unsupported(reason: String)
    /// The engine cannot confirm what to do.
    case cannotConfirm(reason: String)

    /// The user-facing text for the suggestion.
    var text: String {
        switch self {
        case .autoFixable(let action): return action
        case .needsConfirmation(let action): return action
        case .needsRebackup(let action): return action
        case .needsColdRestart(let action): return action
        case .unsupported(let reason): return reason
        case .cannotConfirm(let reason): return reason
        }
    }

    /// The kind label, for the JSON/TXT export.
    var kindLabel: String {
        switch self {
        case .autoFixable: return L("Can be fixed automatically")
        case .needsConfirmation: return L("Needs confirmation")
        case .needsRebackup: return L("Needs a fresh backup")
        case .needsColdRestart: return L("Needs a device restart")
        case .unsupported: return L("Not supported on this system")
        case .cannotConfirm: return L("Cannot confirm")
        }
    }
}

/// One diagnosed issue: a stable code, what it is about, how urgent
/// it is, the evidence it is based on (already redacted), and one of
/// the six suggested fixes.
struct DiagnosticsFinding: Equatable, Sendable, Identifiable {
    var id: String { code }
    /// Stable machine-readable identifier, for example
    /// "ai-live-mismatch" / "sentinel-blocked".
    let code: String
    let category: FindingCategory
    let severity: Severity
    let title: String
    /// Evidence quoted from the inputs, already redacted.
    let evidence: [String]
    let fix: FixSuggestion
}

/// The diagnosis report for one run. Findings are sorted by
/// severity (errors, warnings, notes) in rule order within a
/// severity. `eventsConnected` is true only when structured
/// operation events were supplied: when false, write/restore/guard
/// events are not in this report, because the app does not record
/// them in this run.
struct DiagnosticsReport: Equatable, Sendable {
    let generatedAt: Date
    /// Device + system version + read state, redacted.
    let inputSummary: String
    let findings: [DiagnosticsFinding]
    let versionSentinel: VersionSentinelState
    /// The honest supported range for the current build, as named by
    /// `VersionSentinel.supportedRangeDescription`.
    let supportedRange: String
    let eventsConnected: Bool

    /// The disclaimer every display of this report must carry.
    static let disclaimer = L("A suggested fix is a suggestion, not a guarantee. It may not work on this device.")

    var errorCount: Int { findings.filter { $0.severity == .error }.count }
    var warningCount: Int { findings.filter { $0.severity == .warning }.count }
    var infoCount: Int { findings.filter { $0.severity == .info }.count }
    var hasIssues: Bool { !findings.isEmpty }

    var summary: String {
        if findings.isEmpty {
            return L("No issues were found in the available data.")
        }
        return String(format: L("%d errors, %d warnings, %d notes"), errorCount, warningCount, infoCount)
    }

    func finding(code: String) -> DiagnosticsFinding? {
        findings.first { $0.code == code }
    }
}

// MARK: - Export (JSON / TXT renderers of the same report)

/// The Codable shape of a report for JSON export. Plain strings
/// only, so the export never depends on the engine's enums.
struct DiagnosticsReportExport: Codable, Equatable {
    struct ExportFinding: Codable, Equatable {
        let code: String
        let category: String
        let severity: String
        let title: String
        let evidence: [String]
        let fixKind: String
        let fix: String
    }

    let generatedAt: Date
    let device: String
    let sentinel: String
    let supportedRange: String
    let summary: String
    let disclaimer: String
    let findings: [ExportFinding]
}

extension DiagnosticsReport {
    /// The JSON export of this report: the same findings, redacted,
    /// as a Codable document. Export never writes identifiers: every
    /// evidence string was redacted at construction, and the device
    /// line carries product/model strings only.
    func exportJSON() throws -> Data {
        let export = DiagnosticsReportExport(
            generatedAt: generatedAt,
            device: inputSummary,
            sentinel: String(describing: versionSentinel),
            supportedRange: supportedRange,
            summary: summary,
            disclaimer: Self.disclaimer,
            findings: findings.map { finding in
                DiagnosticsReportExport.ExportFinding(
                    code: finding.code,
                    category: finding.category.rawValue,
                    severity: finding.severity.rawValue,
                    title: finding.title,
                    evidence: finding.evidence,
                    fixKind: finding.fix.kindLabel,
                    fix: finding.fix.text)
            })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(export)
    }

    /// The plain-text export of this report (localized). Same
    /// findings, same redaction, one section per finding.
    func exportText() -> String {
        var lines: [String] = []
        lines.append(L("Diagnostics Report"))
        lines.append(String(format: L("Generated: %@"), ISO8601DateFormatter().string(from: generatedAt)))
        lines.append(String(format: L("Device: %@"), inputSummary))
        lines.append(String(format: L("Supported range: %@"), supportedRange))
        lines.append(String(format: L("Summary: %@"), summary))
        lines.append(Self.disclaimer)
        lines.append("")
        for finding in findings {
            lines.append("[\(finding.severity.rawValue.uppercased())] \(finding.title) (\(finding.code))")
            for evidence in finding.evidence {
                lines.append("  - \(evidence)")
            }
            lines.append("  \(finding.fix.kindLabel): \(finding.fix.text)")
            lines.append("")
        }
        return LilaLog.redact(lines.joined(separator: "\n"))
    }
}

// MARK: - Engine

/// Pure diagnosis over explicit inputs. Reads its inputs, writes
/// nothing, performs no file I/O. One finding per issue code at
/// most: the same issue seen through two inputs is reported once,
/// with the evidence from both.
enum DiagnosticsEngine {
    /// The seven AI capability ids (task-book §5.2's chain is about
    /// these keys).
    private static let aiCapabilityIDs = Set(ChinaUnlock.aiCapabilityIDs)

    static func report(_ input: DiagnosticsInput, now: Date = Date()) -> DiagnosticsReport {
        var ordered: [(order: Int, finding: DiagnosticsFinding)] = []
        var seen = Set<String>()
        func add(_ finding: DiagnosticsFinding) {
            guard seen.insert(finding.code).inserted else { return }
            // Evidence is redacted at construction: no finding can
            // leak a device identifier, whatever its inputs held.
            let redacted = DiagnosticsFinding(
                code: finding.code, category: finding.category,
                severity: finding.severity, title: finding.title,
                evidence: finding.evidence.map(LilaLog.redact), fix: finding.fix)
            ordered.append((order: ordered.count, finding: redacted))
        }

        diagnoseSentinel(input, add: add)
        diagnoseReadState(input, add: add)
        diagnoseAI(input, add: add)
        diagnoseMonitorDifferences(input, add: add)
        diagnoseSlotBaseline(input, add: add)
        diagnoseBackups(input, add: add)
        diagnoseRestoreReports(input, add: add)
        diagnoseFingerprint(input, add: add)
        diagnoseEvents(input, add: add)
        diagnoseStaleMonitor(input, add: add)

        let findings = ordered
            .sorted { left, right in
                if left.finding.severity.sortOrder != right.finding.severity.sortOrder {
                    return left.finding.severity.sortOrder < right.finding.severity.sortOrder
                }
                return left.order < right.order
            }
            .map { entry in entry.finding }
        let sentinel = VersionSentinel.state(forBuild: input.device?.osBuild)
        return DiagnosticsReport(
            generatedAt: now,
            inputSummary: inputSummary(for: input),
            findings: findings,
            versionSentinel: sentinel,
            supportedRange: VersionSentinel.supportedRangeDescription(for: sentinel),
            eventsConnected: !input.events.isEmpty)
    }

    /// The one-line input summary: device + system version + read
    /// state. Product/model strings only — never an identifier.
    private static func inputSummary(for input: DiagnosticsInput) -> String {
        let devicePart: String = {
            guard let device = input.device else { return L("Device not read yet") }
            var parts: [String] = []
            if let product = device.productType { parts.append(product) }
            if let version = device.osVersion { parts.append("iOS \(version)") }
            if let build = device.osBuild { parts.append("(\(build))") }
            return parts.isEmpty ? L("Device not read yet") : parts.joined(separator: " ")
        }()
        let readPart: String = {
            switch input.mgReadState {
            case .live(_, let readAt):
                return String(format: L("live read at %@"), ISO8601DateFormatter().string(from: readAt))
            case .readFailed(let reason):
                return L("read failed: ") + reason
            case .notReadYet:
                return L("not read yet")
            }
        }()
        return "\(devicePart) · \(readPart)"
    }

    // MARK: - Sentinel (ADR-2-09)

    private static func diagnoseSentinel(_ input: DiagnosticsInput, add: (DiagnosticsFinding) -> Void) {
        let sentinel = VersionSentinel.state(forBuild: input.device?.osBuild)
        switch sentinel {
        case .supported:
            break
        case .blocked(let build):
            add(DiagnosticsFinding(
                code: "sentinel-blocked",
                category: .device,
                severity: .error,
                title: L("This iOS version blocks the mechanism"),
                evidence: [String(format: L("Build %@: %@"), build,
                                  VersionSentinel.supportedRangeDescription(for: sentinel))],
                fix: .unsupported(reason: VersionSentinel.guidance(for: sentinel)
                    ?? L("This iOS version blocks the mechanism."))))
        case .unknownBuild(let build):
            add(DiagnosticsFinding(
                code: "sentinel-unknown-build",
                category: .device,
                severity: .warning,
                title: L("iOS build could not be confirmed"),
                evidence: [String(format: L("Build %@: %@"), build.isEmpty ? L("unknown") : build,
                                  VersionSentinel.supportedRangeDescription(for: sentinel))],
                fix: .cannotConfirm(reason: VersionSentinel.guidance(for: sentinel)
                    ?? L("The iOS build could not be confirmed."))))
        }
    }

    // MARK: - Read state

    private static func diagnoseReadState(_ input: DiagnosticsInput, add: (DiagnosticsFinding) -> Void) {
        switch input.mgReadState {
        case .notReadYet:
            add(DiagnosticsFinding(
                code: "device-never-read",
                category: .device,
                severity: .info,
                title: L("Device not read yet"),
                evidence: [],
                fix: .autoFixable(action: L("Read the device to see its current state."))))
        case .readFailed(let reason):
            add(DiagnosticsFinding(
                code: "mg-read-failed",
                category: .mgRead,
                severity: .error,
                title: L("MobileGestalt read failed"),
                evidence: [reason],
                fix: .cannotConfirm(reason: L("The read failed. Re-read the device."))))
        case .live:
            break
        }
    }
}

// MARK: - AI chain (task-book §5.2), monitor, slots, backups, restore, fingerprint, events

extension DiagnosticsEngine {
    /// The seven AI capabilities with their MG key and "on" value.
    /// A capability with no per-key value stages a plain Boolean 1.
    private static func aiKeys() -> [(capabilityID: String, key: String, onValue: MGValue)] {
        ChinaUnlock.aiCapabilities.compactMap { capability in
            guard let key = capability.keys.first else { return nil }
            let onValue = capability.values[key].flatMap(MGValue.fromPlistValue) ?? .bool(true)
            return (capability.id, key, onValue)
        }
    }

    /// The §5.2 chain for "Apple Intelligence enabled but not
    /// working", one finding per failed check, in order:
    /// fields staged -> live re-read -> write success -> cold
    /// restart -> dependencies. Hardware support is implicit: on
    /// native hardware the not-staged and region checks do not apply
    /// (AI is on natively). The system-version check lives in the
    /// sentinel rule — one owner, no duplicates — and is referenced
    /// here only through the live values.
    private static func diagnoseAI(_ input: DiagnosticsInput, add: (DiagnosticsFinding) -> Void) {
        let keys = aiKeys()
        guard !keys.isEmpty else { return }
        let staged = input.workingValues
        var liveByKey: [String: MGValue] = [:]
        for row in input.monitorRows {
            if let live = row.live { liveByKey[row.record.obfuscatedName] = live }
        }
        let isNative = input.device?.isNativeAppleIntelligence ?? false
        let stagedKeys = keys.filter { staged[$0.key] != nil }

        // 1. Fields: no AI key staged, and the live answers show
        // them off. When no live value is known at all the rule stays
        // silent — unreadable is covered by the monitor/read rules.
        if !isNative {
            let liveKnown = keys.compactMap { liveByKey[$0.key] }
            let liveOn = keys.contains { liveByKey[$0.key] == $0.onValue }
            if stagedKeys.isEmpty && !liveOn && !liveKnown.isEmpty {
                add(DiagnosticsFinding(
                    code: "ai-not-staged",
                    category: .compatibility,
                    severity: .warning,
                    title: L("Apple Intelligence keys are not staged"),
                    evidence: [L("None of the 7 AI keys is staged, and the live answers show them off.")],
                    fix: .needsConfirmation(action: L("Stage the AI preset (one-tap unlock or AI Only) so the 7 AI keys are staged."))))
            }
        }

        // 2. Re-read: a staged AI key whose live value differs.
        let mismatched = keys.filter { key in
            guard let stagedValue = staged[key.key], let live = liveByKey[key.key] else { return false }
            return stagedValue != live
        }
        if !mismatched.isEmpty {
            add(DiagnosticsFinding(
                code: "ai-live-mismatch",
                category: .mgWrite,
                severity: .warning,
                title: L("Staged AI values are not live yet"),
                evidence: mismatched.map { key in
                    String(format: L("%@: staged %@, live %@"), key.capabilityID,
                           staged[key.key]?.displayText ?? L("absent"),
                           liveByKey[key.key]?.displayText ?? L("unreadable"))
                },
                fix: .needsColdRestart(action: L("Restart the device, then re-read: the staged AI values are not what the device reports live."))))
        }

        // 3. Write success: a failed AI write event.
        let writeFailed = input.events.filter { event in
            guard event.kind == .writeFailed else { return false }
            if let key = event.key { return keys.contains { $0.key == key } }
            if let featureID = event.featureID { return aiCapabilityIDs.contains(featureID) }
            return false
        }
        if !writeFailed.isEmpty {
            add(DiagnosticsFinding(
                code: "ai-write-failed",
                category: .mgWrite,
                severity: .error,
                title: L("An Apple Intelligence write did not verify"),
                evidence: writeFailed.prefix(3).map(\.detail),
                fix: .needsRebackup(action: L("Create a fresh backup, then retry the AI write."))))
        }

        // 4. Cold restart: AI changes applied but not yet verified
        // after a restart.
        let pendingAI = input.pendingRestartFeatureIDs.intersection(aiCapabilityIDs)
        if !pendingAI.isEmpty {
            add(DiagnosticsFinding(
                code: "ai-restart-pending",
                category: .compatibility,
                severity: .info,
                title: L("Apple Intelligence changes await a restart check"),
                evidence: [String(format: L("Applied but not yet verified after a restart: %@"),
                                  pendingAI.sorted().joined(separator: ", "))],
                fix: .needsColdRestart(action: L("Restart the device: the AI changes are applied but not yet verified after a restart."))))
        }

        // 5. Dependencies: AI is staged (or live on) but the region
        // is not LL — on non-native hardware Apple Intelligence
        // depends on it.
        if !isNative, let region = input.device?.regionCode, region != "LL" {
            let aiActive = !stagedKeys.isEmpty || keys.contains { liveByKey[$0.key] == $0.onValue }
            if aiActive {
                add(DiagnosticsFinding(
                    code: "ai-region-dependency",
                    category: .compatibility,
                    severity: .warning,
                    title: L("Apple Intelligence needs region LL"),
                    evidence: [String(format: L("Region code is %@, not LL."), region)],
                    fix: .needsConfirmation(action: L("Change the region code to LL: Apple Intelligence depends on it on non-native hardware."))))
            }
        }
    }

    /// Monitor rows whose sources disagree, aggregated into one
    /// finding (a row per key would drown the report at 77 keys).
    private static func diagnoseMonitorDifferences(_ input: DiagnosticsInput, add: (DiagnosticsFinding) -> Void) {
        let differing = input.monitorRows.filter { $0.hasDifference }
        guard !differing.isEmpty else { return }
        var evidence: [String] = []
        for row in differing.prefix(5) {
            evidence.append(String(format: L("%@: original %@, staged %@, live %@"),
                                   row.record.readableName,
                                   row.original?.displayText ?? L("absent"),
                                   row.staged?.displayText ?? L("absent"),
                                   row.live?.displayText ?? L("unreadable")))
        }
        if differing.count > 5 {
            evidence.append(String(format: L("And %d more differing keys."), differing.count - 5))
        }
        let needsRestart = differing.contains { row in
            guard let staged = row.staged, let live = row.live else { return false }
            return staged != live
        }
        add(DiagnosticsFinding(
            code: "monitor-differences",
            category: .compatibility,
            severity: .warning,
            title: L("Live values differ from the staged values"),
            evidence: evidence,
            fix: needsRestart
                ? .needsColdRestart(action: L("Restart the device, then re-read: the live values still differ from the staged values."))
                : .needsConfirmation(action: L("Apply or discard the staged changes, then re-read."))))
    }

    /// Slot rows whose live answer disagrees with the native
    /// baseline (#178/#266). Unknown baselines are not disagreements.
    private static func diagnoseSlotBaseline(_ input: DiagnosticsInput, add: (DiagnosticsFinding) -> Void) {
        var disagreeing: [MGMonitorRow] = []
        for row in input.monitorRows {
            if row.slot?.disagreesWithNativeBaseline == true { disagreeing.append(row) }
        }
        guard !disagreeing.isEmpty else { return }
        let evidence = disagreeing.prefix(5).map { row in
            let slot = row.slot
            return String(format: L("%@: live %@, native baseline %@"),
                          row.record.readableName,
                          slot?.liveAnswer.map { $0 ? "true" : "false" } ?? L("unknown"),
                          slot?.nativeBaseline.map { $0 ? "true" : "false" } ?? L("unknown"))
        }
        add(DiagnosticsFinding(
            code: "slot-baseline-disagreement",
            category: .conflict,
            severity: .warning,
            title: L("An Apple Intelligence slot disagrees with its native baseline"),
            evidence: Array(evidence),
            fix: .needsConfirmation(action: L("Restore the slot to its native value from a verified backup."))))
    }

    private static func diagnoseBackups(_ input: DiagnosticsInput, add: (DiagnosticsFinding) -> Void) {
        if input.backups.isEmpty {
            add(DiagnosticsFinding(
                code: "backup-none",
                category: .backup,
                severity: .info,
                title: L("No backups yet"),
                evidence: [],
                fix: .autoFixable(action: L("Create a backup before changing anything."))))
            return
        }
        let failed = input.backupVerifications.filter { verification in
            switch verification.status {
            case .failed, .notFound: return true
            case .verified, .legacyNoDigest: return false
            }
        }
        if !failed.isEmpty {
            add(DiagnosticsFinding(
                code: "backup-failed",
                category: .backup,
                severity: .error,
                title: L("A backup could not be verified"),
                evidence: failed.prefix(3).map { verification in
                    String(format: L("Backup “%@” — verification failed."), verification.record.reason)
                },
                fix: .needsRebackup(action: L("Create a fresh backup. A failed backup cannot be used to restore."))))
            return
        }
        let legacyOnly = !input.backupVerifications.isEmpty
            && input.backupVerifications.allSatisfy { verification in
                if case .legacyNoDigest = verification.status { return true }
                return false
            }
        if legacyOnly {
            add(DiagnosticsFinding(
                code: "backup-legacy-only",
                category: .backup,
                severity: .warning,
                title: L("Backups have no recorded digest"),
                evidence: [L("Every verified backup is a legacy backup with no recorded digest, so integrity cannot be proven.")],
                fix: .needsConfirmation(action: L("Create a fresh backup with a recorded digest. Restore from a legacy backup only after explicit confirmation."))))
        } else if input.backupVerifications.isEmpty {
            add(DiagnosticsFinding(
                code: "backup-unverified",
                category: .backup,
                severity: .info,
                title: L("Backups have not been verified"),
                evidence: [],
                fix: .autoFixable(action: L("Verify the backups before relying on one."))))
        }
    }

    /// The fix for a failed restore-pipeline step.
    private static func fix(forFailedStep step: RestoreEngine.Step) -> FixSuggestion {
        switch step {
        case .verifyIntegrity, .backUpFirst:
            return .needsRebackup(action: L("Create a fresh backup before retrying the restore."))
        case .verifyDeviceIdentity:
            return .cannotConfirm(reason: L("This backup does not belong to this device."))
        case .verifyVersionCompatibility:
            return .unsupported(reason: L("This iOS version blocks the mechanism. Stay on iOS 27.2.1 or below."))
        case .preview:
            return .needsConfirmation(action: L("Review the restore preview: a check failed."))
        case .execute, .readBackVerify, .report:
            return .cannotConfirm(reason: L("The restore step failed. Check the restore report for the detail."))
        }
    }

    private static func diagnoseRestoreReports(_ input: DiagnosticsInput, add: (DiagnosticsFinding) -> Void) {
        let failed = input.restoreReports.filter { !$0.succeeded }
        guard !failed.isEmpty else { return }
        var evidence: [String] = []
        var suggestion: FixSuggestion = .cannotConfirm(reason: L("The restore did not complete. Check the restore report for the failed step."))
        for (index, report) in failed.prefix(3).enumerated() {
            guard let firstFailed = report.outcomes.first(where: { !$0.passed }) else { continue }
            evidence.append(String(format: L("Backup “%@”: %@ — %@"),
                                   report.plan.record.reason, firstFailed.step.rawValue, firstFailed.detail))
            if index == 0 { suggestion = fix(forFailedStep: firstFailed.step) }
        }
        add(DiagnosticsFinding(
            code: "restore-failed",
            category: .restore,
            severity: .error,
            title: L("A restore did not complete"),
            evidence: evidence,
            fix: suggestion))
    }

    private static func diagnoseFingerprint(_ input: DiagnosticsInput, add: (DiagnosticsFinding) -> Void) {
        guard let comparison = input.fingerprintComparison, comparison.hasChanges else { return }
        if comparison.differentDevice {
            add(DiagnosticsFinding(
                code: "fingerprint-different-device",
                category: .device,
                severity: .error,
                title: L("The stored fingerprint is from a different device"),
                evidence: [],
                fix: .cannotConfirm(reason: L("The stored fingerprint belongs to a different device, so the recorded support scope does not apply here."))))
            return
        }
        let evidence = comparison.changes.prefix(5).map { change in
            "\(change.displayName): \(change.old) → \(change.new)"
        }
        add(DiagnosticsFinding(
            code: "fingerprint-changed",
            category: .device,
            severity: .warning,
            title: L("The device fingerprint changed"),
            evidence: Array(evidence),
            fix: .needsConfirmation(action: L("Review the changed fields. If the change is expected, re-capture the fingerprint."))))
    }

    /// One finding per failed/guard event kind present, with the
    /// observed details as evidence. Success kinds carry no finding.
    private static func diagnoseEvents(_ input: DiagnosticsInput, add: (DiagnosticsFinding) -> Void) {
        let mapping: [(kind: OperationEventKind, severity: Severity, category: FindingCategory, fix: FixSuggestion)] = [
            (.writeFailed, .error, .mgWrite,
             .needsRebackup(action: L("Create a fresh backup, then retry the write."))),
            (.restoreFailed, .error, .restore,
             .needsRebackup(action: L("Create a fresh backup before retrying the restore."))),
            (.readFailed, .error, .mgRead,
             .cannotConfirm(reason: L("The read failed. Re-read the device."))),
            (.guardLayoutUnresolved, .warning, .conflict,
             .cannotConfirm(reason: L("The cache layout could not be resolved on this model and OS build."))),
            (.guardHardwareIdentity, .warning, .conflict,
             .cannotConfirm(reason: L("The proposal touched a hardware-identity field. Remove it from the proposal."))),
            (.guardNativeConflict, .warning, .conflict,
             .needsConfirmation(action: L("On native Apple Intelligence hardware, skip this item: the native slot stays off."))),
            (.slotUnresolvable, .warning, .conflict,
             .needsConfirmation(action: L("The CacheData slot could not be located on this device's layout."))),
            (.backupFailed, .error, .backup,
             .needsRebackup(action: L("Create a fresh backup. This record cannot be used to restore."))),
            (.regionReverted, .warning, .compatibility,
             .needsRebackup(action: L("If the region keeps reverting, restore from a verified backup."))),
        ]
        for entry in mapping {
            let events = input.events.filter { $0.kind == entry.kind }
            guard !events.isEmpty else { continue }
            add(DiagnosticsFinding(
                code: "event-\(entry.kind.rawValue)",
                category: entry.category,
                severity: entry.severity,
                title: entry.kind.title,
                evidence: events.prefix(3).map(\.detail),
                fix: entry.fix))
        }
    }

    private static func diagnoseStaleMonitor(_ input: DiagnosticsInput, add: (DiagnosticsFinding) -> Void) {
        guard input.monitorRows.contains(where: { $0.isStale }) else { return }
        add(DiagnosticsFinding(
            code: "monitor-stale",
            category: .mgRead,
            severity: .info,
            title: L("Monitor values are stale"),
            evidence: [L("The live values were read more than five minutes ago.")],
            fix: .autoFixable(action: L("Refresh the monitor to re-read the live values."))))
    }
}
