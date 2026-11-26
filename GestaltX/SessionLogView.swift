// SPDX-License-Identifier: GPL-3.0-only
// Session log view, split out of ContentView.swift in Stage 3.
import SwiftUI

struct SessionLogView: View {
    @EnvironmentObject private var model: GestaltManager
    @State private var export: TemporaryExport?

    private func shareLog() {
        let text = model.logs.joined(separator: "\n") + "\n"
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let name = "GestaltX-session-\(Int(Date.now.timeIntervalSince1970)).log"
        export = try? TemporaryExport(data: Data(text.utf8), name: name)
    }

    var body: some View {
        Group {
            if model.logs.isEmpty {
                Text(L("No activity yet."))
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .environment(\.layoutDirection, .leftToRight)
            } else {
                // Rows render lazily: the old single Text laid out up
                // to 1000 joined lines at once. The log is append-only,
                // so indices are stable identities for existing rows.
                List(model.logs.indices, id: \.self) { index in
                    Text(model.logs[index])
                        .font(.system(.caption, design: .monospaced))
                        .environment(\.layoutDirection, .leftToRight)
                }
                .listStyle(.plain)
                .textSelection(.enabled)
            }
        }
        .navigationTitle(L("Session Log"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { shareLog() } label: { Image(systemName: "square.and.arrow.up") }
                    .disabled(model.logs.isEmpty)
                    .accessibilityLabel(L("Share Log"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(L("Clear")) { model.clearLog() }
            }
        }
        .sheet(item: $export) { ShareSheet(export: $0) }
    }
}
