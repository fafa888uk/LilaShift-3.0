// SPDX-License-Identifier: GPL-3.0-only
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class UnifiedOperationLog: ObservableObject {
    enum Area: String, Codable { case plist, screen, network }
    enum Level: String, CaseIterable, Codable, Identifiable {
        case info, warning, error
        var id: Self { self }
        var title: String {
            switch self {
            case .info: "信息"
            case .warning: "警告"
            case .error: "错误"
            }
        }
    }

    struct Event: Codable, Identifiable {
        let id: UUID
        let time: Date
        let area: Area
        let level: Level
        let event: String
    }

    @Published private(set) var entries: [Event] = []

    /// Only controlled event names: no paths, reports, IPs or setting values.
    func record(_ area: Area, _ level: Level, _ event: String) {
        entries.append(.init(id: UUID(), time: .now, area: area, level: level, event: event))
        if entries.count > 500 { entries.removeFirst(entries.count - 500) }
    }
}

@MainActor
struct UnifiedOperationLogView: View {
    @EnvironmentObject private var log: UnifiedOperationLog
    @State private var text = ""
    @State private var level: UnifiedOperationLog.Level?
    @State private var exporting = false
    @State private var document: JSONDocument?
    @State private var exportFailed = false

    private struct JSONDocument: FileDocument {
        static var readableContentTypes: [UTType] { [.json] }
        let bytes: Data
        init(bytes: Data) { self.bytes = bytes }
        init(configuration: ReadConfiguration) throws {
            guard let bytes = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
            self.bytes = bytes
        }
        func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: bytes) }
    }

    private var matched: [UnifiedOperationLog.Event] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return log.entries.reversed().filter {
            (level == nil || level == $0.level) &&
            (query.isEmpty || $0.event.localizedCaseInsensitiveContains(query) || $0.area.rawValue.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        List {
            Section {
                Picker("日志级别", selection: $level) {
                    Text("全部").tag(nil as UnifiedOperationLog.Level?)
                    ForEach(UnifiedOperationLog.Level.allCases) { row in
                        Text(row.title).tag(Optional(row))
                    }
                }
                Button("导出当前筛选结果", systemImage: "square.and.arrow.up") { prepareExport() }
                    .disabled(matched.isEmpty)
            } footer: {
                Text("仅本次应用会话内的真实操作，最多 500 条。不记录文件内容、路径或网络地址。")
            }
            if matched.isEmpty {
                Text(log.entries.isEmpty ? "本次会话还没有可记录的操作。" : "没有匹配的日志。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(matched) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.event)
                        Text(item.level.title + " · " + item.area.rawValue + " · " + item.time.formatted())
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("会话日志")
        .searchable(text: $text)
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "LilaShift-Session-Log") {
            if case .failure = $0 { exportFailed = true }
            document = nil
        }
        .alert("未能导出日志", isPresented: $exportFailed) {
            Button("好", role: .cancel) {}
        }
    }

    private func prepareExport() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            document = .init(bytes: try encoder.encode(matched))
            exporting = true
        } catch { exportFailed = true }
    }
}
