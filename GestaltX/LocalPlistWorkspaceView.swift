// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct LocalPlistWorkspaceView: View {
    @EnvironmentObject private var operationLog: UnifiedOperationLog
    @State private var records: [LocalPlistWorkspace.Record] = []
    @State private var selected: LocalPlistWorkspace.Record?
    @State private var draft = ""
    @State private var proposal: LocalPlistWorkspace.Change?
    @State private var notice: String?
    @State private var importing = false
    @State private var restoring = false
    @State private var restoreLast = false
    @State private var exporting = false
    @State private var document: CopyDocument?

    private struct CopyDocument: FileDocument {
        static var readableContentTypes: [UTType] { [.propertyList] }
        let bytes: Data

        init(bytes: Data) { self.bytes = bytes }

        init(configuration: ReadConfiguration) throws {
            guard let bytes = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
            self.bytes = bytes
        }

        func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
            FileWrapper(regularFileWithContents: bytes)
        }
    }

    private var store: LocalPlistWorkspace {
        .init(root: URL.applicationSupportDirectory.appending(path: "LocalPlistWorkspace", directoryHint: .isDirectory))
    }

    var body: some View {
        List {
            Section {
                Button("导入 plist 副本", systemImage: "doc.badge.plus") { importing = true }
                ForEach(records) { record in
                    Button { select(record) } label: {
                        Label(record.name, systemImage: record.id == selected?.id ? "checkmark.circle.fill" : "doc")
                    }
                }
            } footer: {
                Text("只编辑应用内的独立副本，不修改来源文件、系统设置或 MobileGestalt。")
            }

            if let selected {
                Section("副本编辑") {
                    TextEditor(text: $draft)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 180)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityLabel("plist XML")
                    Button("检查差异", systemImage: "arrow.left.arrow.right") { prepare(selected) }
                }

                if let proposal {
                    Section("写入前核对") {
                        LabeledContent("变更字段", value: proposal.changedKeys.count.formatted())
                        ForEach(proposal.changedKeys.prefix(25), id: \.self) { Text($0) }
                        if proposal.changedKeys.count > 25 { Text("这里只列出前 25 项。") }
                        Text("原 SHA256：\(proposal.beforeSHA)").font(.caption.monospaced())
                        Text("新 SHA256：\(proposal.afterSHA)").font(.caption.monospaced())
                        Button("写入副本并校验", systemImage: "checkmark.shield") { apply(proposal) }
                    }
                }

                Section("备份与恢复") {
                    Button("导出当前副本") { export(selected.working) }
                    Button("导出原始备份") { export(selected.original) }
                    if let before = selected.previous, selected.previousSHA != selected.workingSHA {
                        Button("导出上次写入前的备份") { export(before) }
                        Button("恢复上次写入前的备份", role: .destructive) { restoreLast = true; restoring = true }
                    }
                    if selected.workingSHA != selected.originalSHA {
                        Button("恢复原始备份", role: .destructive) { restoreLast = false; restoring = true }
                    }
                }
            }

            if let notice { Text(notice).foregroundStyle(.secondary) }
        }
        .navigationTitle("本地 plist 工作区")
        .onChange(of: draft) { _, _ in proposal = nil }
        .task { refresh() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.propertyList]) { result in
            guard case .success(let url) = result else { return }
            Task { await importFile(url) }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .propertyList, defaultFilename: "LilaShift-Local.plist") {
            if case .success = $0 { notice = "文件已导出。" }
            else { notice = "导出未完成。" }
            document = nil
        }
        .confirmationDialog("用核对过的备份恢复当前副本？", isPresented: $restoring, titleVisibility: .visible) {
            Button("恢复并校验", role: .destructive) { restore() }
        } message: {
            if let selected {
                let target = restoreLast ? selected.previousSHA : selected.originalSHA
                Text("当前 SHA256：\(selected.workingSHA)\n恢复目标：\(target ?? "不可读")")
            }
        }
    }

    private func refresh() {
        do { records = try store.records() }
        catch { notice = "无法载入本地副本；未修改文件。" }
    }

    private func importFile(_ url: URL) async {
        do {
            let data = try await Task.detached { try LocalPlistWorkspace.readSelectedFile(url) }.value
            _ = try LocalPlistWorkspace.editableXML(data)
            let imported = try store.importCopy(data, name: url.lastPathComponent)
            select(imported)
            refresh()
            notice = "副本与原始备份已写入并读回校验。"
            operationLog.record(.plist, .info, "导入副本，已校验原始备份")
        } catch {
            operationLog.record(.plist, .error, "导入副本未完成")
            notice = "导入未完成。需要不超过 1 MiB 的有效字典 plist，且不能是链接。"
        }
    }

    private func select(_ record: LocalPlistWorkspace.Record) {
        do {
            draft = try LocalPlistWorkspace.editableXML(record.working)
            selected = record
            proposal = nil
            notice = nil
        } catch { notice = "无法打开此副本。" }
    }

    private func prepare(_ record: LocalPlistWorkspace.Record) {
        do { proposal = try store.stage(xml: draft, for: record); notice = nil }
        catch LocalPlistWorkspace.Failure.noChange { proposal = nil; notice = "没有字段变化。" }
        catch { proposal = nil; notice = "无法生成差异，请核对 XML 格式及大小。" }
    }

    private func apply(_ change: LocalPlistWorkspace.Change) {
        guard Data(draft.utf8) == change.bytes else { proposal = nil; return }
        do {
            selected = try store.apply(change)
            proposal = nil
            refresh()
            notice = "副本已保存，读回的 SHA256 与本次差异一致。"
            operationLog.record(.plist, .info, "保存副本，已读回核对")
        } catch {
            proposal = nil
            notice = "未能确认写入；请重新打开副本核对，原始备份未替换。"
            operationLog.record(.plist, .error, "副本写入未得到读回确认")
        }
    }

    private func restore() {
        guard let selected else { return }
        do {
            let verified = try restoreLast
                ? store.restorePrevious(id: selected.id, expectedSHA: selected.workingSHA)
                : store.restoreOriginal(id: selected.id, expectedSHA: selected.workingSHA)
            select(verified)
            refresh()
            notice = "恢复后读回的内容与所选备份一致。"
            operationLog.record(.plist, .info, "恢复副本，已读回核对")
        } catch {
            notice = "未能确认恢复；请重新打开副本核对。"
            operationLog.record(.plist, .error, "副本恢复未得到读回确认")
        }
    }

    private func export(_ bytes: Data) {
        document = .init(bytes: bytes)
        exporting = true
    }
}
