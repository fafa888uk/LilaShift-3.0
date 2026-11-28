// SPDX-License-Identifier: GPL-3.0-only
// Structured log view (LilaShift 5.0.0, Wave 1 W2) — the viewer
// for `StructuredLog`: level badges, keyword search, level / kind
// / source / date filters, and a share action that exports the
// entries currently shown (after filters) as JSON or text through
// the system share sheet (`ShareSheet`, as in `SessionLogView`).
//
// The view only shows what LilaShift itself logged this session:
// structured operation events from `OperationEventRecorder` and
// the free-text session log. It shows no network request records —
// LilaShift makes almost no network requests of its own — and it
// repeats the coverage note that write, restore and guard events
// are not recorded yet, instead of presenting the log as complete.
import SwiftUI

struct StructuredLogView: View {
    @EnvironmentObject private var model: GestaltManager

    @State private var recordedEvents: [OperationEvent] = []
    @State private var searchText = ""
    @State private var selectedLevels: Set<StructuredLogLevel> = []
    @State private var selectedKind: OperationEventKind? = nil
    @State private var selectedSource: StructuredLogSource? = nil
    @State private var filterByDate = false
    @State private var filterDate = Date()
    @State private var export: TemporaryExport? = nil
    @State private var exportError: String? = nil

    private var snapshot: OperationLogSnapshot {
        OperationLogSnapshot(events: recordedEvents, freeTextLines: model.logs)
    }

    private var allEntries: [StructuredLogEntry] {
        StructuredLog.entries(from: snapshot)
    }

    private var filter: StructuredLogFilter {
        var filter = StructuredLogFilter()
        filter.keyword = searchText
        filter.levels = selectedLevels
        if let selectedKind {
            filter.kinds = [selectedKind]
        }
        filter.source = selectedSource
        if filterByDate {
            let range = StructuredLogFilter.dayRange(for: filterDate)
            filter.fromDate = range.from
            filter.toDate = range.to
        }
        return filter
    }

    private var visibleEntries: [StructuredLogEntry] {
        filter.applying(to: allEntries)
    }

    private var counts: [StructuredLogLevel: Int] {
        StructuredLog.countsByLevel(allEntries)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(OperationLogSnapshot.writeAndRestoreNote)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(L("This log contains only this app's own operation events and session log lines. It contains no network request records."))
                .font(.caption)
                .foregroundStyle(.secondary)
            searchField
            levelFilterRow
            kindAndSourceRow
            dateFilterRow
            summaryLine
            if visibleEntries.isEmpty {
                emptyState
            } else {
                List(visibleEntries) { entry in
                    logRow(entry)
                }
                .listStyle(.plain)
            }
            if let exportError {
                Text(exportError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal)
        .navigationTitle(L("Structured Log"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(L("Refresh")) {
                    Task {
                        recordedEvents = await model.operationEvents.recordedEvents()
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(L("Export as JSON")) { shareLog(format: .json) }
                    Button(L("Export as Text")) { shareLog(format: .text) }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(allEntries.isEmpty)
                .accessibilityLabel(L("Share Log"))
            }
        }
        .sheet(item: $export) { ShareSheet(export: $0) }
        .task {
            recordedEvents = await model.operationEvents.recordedEvents()
        }
    }

    /// Exports the entries currently shown (after filters), so a
    /// filtered export shares only what the user selected.
    private func shareLog(format: StructuredLogExportFormat) {
        do {
            exportError = nil
            export = try StructuredLogExporter.temporaryExport(for: visibleEntries, format: format)
        } catch {
            exportError = L("The log could not be exported.")
        }
    }

    private var searchField: some View {
        TextField(L("Search logs"), text: $searchText)
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
    }

    private var levelFilterRow: some View {
        HStack(spacing: 8) {
            Text(L("Level") + ":")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(StructuredLogLevel.allCases, id: \.self) { level in
                levelToggle(level)
            }
            if !selectedLevels.isEmpty {
                Button(L("All")) { selectedLevels = [] }
                    .font(.subheadline)
            }
        }
    }

    private func levelToggle(_ level: StructuredLogLevel) -> some View {
        Button {
            if selectedLevels.contains(level) {
                selectedLevels.remove(level)
            } else {
                selectedLevels.insert(level)
            }
        } label: {
            Text(level.title)
                .font(.subheadline)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    selectedLevels.contains(level)
                        ? level.color.opacity(0.2)
                        : Color.secondary.opacity(0.12))
                .foregroundStyle(selectedLevels.contains(level) ? level.color : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var kindAndSourceRow: some View {
        HStack(spacing: 8) {
            Menu {
                Button(L("All kinds")) { selectedKind = nil }
                ForEach(StructuredLog.allKinds, id: \.self) { kind in
                    Button(kind.title) { selectedKind = kind }
                }
            } label: {
                Text(selectedKind?.title ?? L("All kinds"))
                    .font(.subheadline)
            }
            Menu {
                Button(L("All sources")) { selectedSource = nil }
                ForEach(StructuredLogSource.allCases, id: \.self) { source in
                    Button(source.title) { selectedSource = source }
                }
            } label: {
                Text(selectedSource?.title ?? L("All sources"))
                    .font(.subheadline)
            }
            Spacer()
        }
    }

    private var dateFilterRow: some View {
        HStack(spacing: 8) {
            Toggle(L("Filter by date"), isOn: $filterByDate)
                .font(.subheadline)
            if filterByDate {
                DatePicker("", selection: $filterDate, displayedComponents: .date)
                    .labelsHidden()
            }
        }
    }

    private var summaryLine: some View {
        let errorCount = counts[.error] ?? 0
        let warningCount = counts[.warning] ?? 0
        let infoCount = counts[.info] ?? 0
        return Text(String(format: L("%d entries · %d errors · %d warnings · %d info"),
                           allEntries.count, errorCount, warningCount, infoCount))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var emptyState: some View {
        Group {
            if allEntries.isEmpty {
                Text(L("No operation events recorded yet."))
            } else {
                Text(L("No log entries match the current filters."))
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private func logRow(_ entry: StructuredLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Circle()
                    .fill(entry.level.color)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(entry.level.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(entry.level.color)
                Text(entry.date.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? L("unknown time"))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(entry.source.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(entry.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(entry.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension StructuredLogLevel {
    var color: Color {
        switch self {
        case .info: return .secondary
        case .warning: return .orange
        case .error: return .red
        }
    }
}
