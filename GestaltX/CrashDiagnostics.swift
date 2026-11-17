// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// System crash, kernel watchdog and Jetsam OOM-kill analyzer (A8).
/// The mechanism is Erosion-CN's `CrashDiagnosticsView` (Kianuni,
/// GPL-3.0), reimplemented for LilaShift's access helper: `.ips`
/// diagnostic reports are read from the
/// `systemgroup.com.apple.osanalytics` container, parsed, and listed
/// by kind. Reading is the point — the reports are system logs, and
/// this feature never edits one. Deleting old reports is a separate,
/// explicitly confirmed action (`cleanAllReports`) and only removes
/// archived `.ips`/`.crash`/`.panic` files; iOS regenerates them.
///
/// Deleting reports (Stage 6 decision): an explicit
/// "unrecoverable" warning, not a 7-day in-app recycle bin. The
/// reports are system logs iOS regenerates — a bin would duplicate
/// system files into the sandbox for no diagnostic value. The
/// confirmation must say the deletion is permanent and cannot be
/// undone.
///
/// A normal sandboxed app cannot open the osanalytics container, so
/// access is granted through `ContainerAccess` (the bundled
/// `worse_query` escape). When the firmware does not grant the token
/// the scanner reports `.unavailable` instead of pretending to work.
enum DiagnosticEventKind: String, CaseIterable, Equatable {
    case all
    case jetsam
    case crash
    case system
}

struct DiagnosticReportItem: Identifiable, Equatable {
    let id: String
    let fileURL: URL
    let fileName: String
    let kind: DiagnosticEventKind
    let bugType: String
    let processName: String
    let subtitle: String
    let modifiedDate: Date
    let fileSize: Int64
}

enum CrashDiagnostics {
    static let diagnosticReportsDirectory =
        "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.osanalytics/Library/Logs/DiagnosticReports"

    /// The result of a scan: whether the container could be read, and
    /// the parsed reports (newest first).
    struct ScanResult {
        let readable: Bool
        let writable: Bool
        let reports: [DiagnosticReportItem]
        let message: String?
    }

    /// Scans the osanalytics DiagnosticReports directory (and its
    /// `Retired` subdirectory) for `.ips`, `.crash` and `.panic`
    /// files, parses each, and returns them newest first. Returns
    /// `readable: false` when the container cannot be opened.
    static func scan() -> ScanResult {
        let fm = FileManager.default
        let grant = ContainerAccess.grantAccess(path: diagnosticReportsDirectory, requireWrite: true)
        let readGrant = grant.granted
            ? grant
            : ContainerAccess.grantAccess(path: diagnosticReportsDirectory, requireWrite: false)
        guard readGrant.granted, fm.isReadableFile(atPath: diagnosticReportsDirectory) else {
            return ScanResult(readable: false, writable: false, reports: [],
                              message: readGrant.error ?? L("The diagnostic reports container could not be opened on this system version."))
        }
        let writable = fm.isWritableFile(atPath: diagnosticReportsDirectory)
        var urls: [URL] = []
        let root = URL(fileURLWithPath: diagnosticReportsDirectory)
        for dir in [root, root.appendingPathComponent("Retired")] {
            guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for name in names {
                let lower = name.lowercased()
                guard lower.contains(".ips") || lower.hasSuffix(".crash") || lower.hasSuffix(".panic") else { continue }
                let url = dir.appendingPathComponent(name)
                var info = stat()
                if lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG {
                    urls.append(url)
                }
            }
        }
        var items: [DiagnosticReportItem] = []
        for url in urls {
            if let item = parseIPSFile(at: url) {
                items.append(item)
            }
        }
        items.sort { $0.modifiedDate > $1.modifiedDate }
        return ScanResult(readable: true, writable: writable, reports: items, message: nil)
    }

    /// Deletes the given report files. Only regular files under the
    /// DiagnosticReports directory (or its Retired subdirectory) are
    /// removed; anything else is refused. Returns the number deleted.
    @discardableResult
    static func cleanAllReports(_ reports: [DiagnosticReportItem]) -> Int {
        let fm = FileManager.default
        let root = (diagnosticReportsDirectory as NSString).standardizingPath
        var deleted = 0
        for report in reports {
            let path = (report.fileURL.path as NSString).standardizingPath
            guard path.hasPrefix(root) else { continue }
            var info = stat()
            guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { continue }
            if (try? fm.removeItem(atPath: path)) != nil {
                deleted += 1
            }
        }
        return deleted
    }

    /// Parses one `.ips` (or `.crash`/`.panic`) report file. Reads at
    /// most the first 256 KB: the first line is a JSON header
    /// (`bug_type`, `app_name`/`name`), the rest is a JSON body.
    /// Returns `nil` when the file cannot be read.
    static func parseIPSFile(at url: URL) -> DiagnosticReportItem? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        let fileSize = Int64(info.st_size)
        let modifiedDate = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 262_144)) ?? Data()
        return parseIPSData(head, fileName: url.lastPathComponent,
                            modifiedDate: modifiedDate, fileSize: fileSize, fileURL: url)
    }

    /// Pure parser over report bytes, so tests can feed sample
    /// payloads without touching the filesystem.
    static func parseIPSData(_ data: Data, fileName: String, modifiedDate: Date,
                             fileSize: Int64, fileURL: URL) -> DiagnosticReportItem? {
        let text = String(decoding: data, as: UTF8.self)
        var bugType = L("Unknown")
        var processName = fileName
        var subtitle = fileName
        var kind: DiagnosticEventKind = .system

        if let newline = text.firstIndex(of: "\n") {
            let headerLine = String(text[..<newline])
            let bodyPart = String(text[text.index(after: newline)...])
            if let headerData = headerLine.data(using: .utf8),
               let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any] {
                bugType = (header["bug_type"] as? String) ?? bugType
                if let name = header["app_name"] as? String, !name.isEmpty {
                    processName = name
                } else if let name = header["name"] as? String, !name.isEmpty {
                    processName = name
                }
            }
            if bugType == "298" || fileName.localizedCaseInsensitiveContains("JetsamEvent") {
                kind = .jetsam
                processName = L("Jetsam memory protection event")
                if let bodyData = bodyPart.data(using: .utf8),
                   let body = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                    let largest = (body["largestProcess"] as? String) ?? L("Unknown process")
                    var killed: [String] = []
                    if let processes = body["processes"] as? [[String: Any]] {
                        for process in processes {
                            if let reason = process["reason"] as? String, !reason.isEmpty,
                               let name = process["name"] as? String {
                                killed.append("\(name) (\(reason))")
                            }
                        }
                    }
                    subtitle = killed.isEmpty
                        ? String(format: L("Largest memory process: %@"), largest)
                        : String(format: L("Largest: %@ · Killed: %@"), largest, killed.prefix(3).joined(separator: ", "))
                } else {
                    subtitle = L("The kernel Jetsam mechanism cleared background processes after physical memory ran out.")
                }
            } else if bugType == "309" || bugType == "109" {
                kind = .crash
                if let bodyData = bodyPart.data(using: .utf8),
                   let body = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                    if let proc = body["procName"] as? String, !proc.isEmpty {
                        processName = proc
                    }
                    let exception = body["exception"] as? [String: Any]
                    let exceptionType = (exception?["type"] as? String) ?? L("Abnormal exit")
                    let signal = (exception?["signal"] as? String) ?? ""
                    let termination = body["termination"] as? [String: Any]
                    let indicator = (termination?["indicator"] as? String) ?? ""
                    let parts = [exceptionType, signal, indicator].filter { !$0.isEmpty }
                    subtitle = parts.isEmpty ? L("An app or daemon crashed abnormally.") : parts.joined(separator: " · ")
                } else {
                    subtitle = String(format: L("Process crash report (%@)"), fileName)
                }
            } else if bugType == "210" || fileName.localizedCaseInsensitiveContains("panic") {
                kind = .system
                processName = L("Kernel panic / watchdog restart")
                subtitle = String(format: L("A system-level restart record was detected (%@)."), fileName)
            } else {
                kind = .system
                subtitle = String(format: L("System diagnostic event (%@)"), fileName)
            }
        }
        return DiagnosticReportItem(id: fileURL.path, fileURL: fileURL, fileName: fileName,
                                    kind: kind, bugType: bugType, processName: processName,
                                    subtitle: subtitle, modifiedDate: modifiedDate, fileSize: fileSize)
    }
}
