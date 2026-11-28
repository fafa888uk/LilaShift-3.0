// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Network
import SwiftUI

@MainActor
struct NetworkCheckView: View {
    @Environment(\.w8NetworkCounter) private var counter
    @EnvironmentObject private var operationLog: UnifiedOperationLog
    @State private var requestID: UUID?
    @State private var publicIP: String?
    @State private var issue: LocalizedStringKey?

    var body: some View {
        List {
            Section {
                Button("network.check", systemImage: "network") {
                    publicIP = nil
                    issue = nil
                    requestID = UUID()
                }
                .disabled(requestID != nil)
                if requestID != nil { ProgressView() }
                if let publicIP { LabeledContent("network.result", value: publicIP) }
                if let issue { Text(issue).foregroundStyle(.secondary) }
            } footer: {
                Text("network.scope")
            }
        }
        .navigationTitle("network.title")
        .task(id: requestID) {
            guard let id = requestID else { return }
            defer { if requestID == id { requestID = nil } }
            do {
                let value = try await Self.check(counter: counter)
                if !Task.isCancelled {
                    publicIP = value
                    operationLog.record(.network, .info, "网络出口查询完成")
                }
            } catch {
                if !Task.isCancelled {
                    issue = "network.failed"
                    operationLog.record(.network, .warning, "网络出口查询未完成")
                }
            }
        }
    }

    private struct Response: Decodable {
        struct Payload: Decodable { let ip: String }
        let status: String
        let data: Payload
    }

    private static func check(counter: W8NetworkCounter?) async throws -> String {
        guard let url = URL(string: "https://stat.ripe.net/data/whats-my-ip/data.json") else {
            throw URLError(.badURL)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        let (stream, response) = try await session.bytes(from: url, delegate: counter)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, http.url?.host == url.host else {
            throw URLError(.badServerResponse)
        }
        var buffer = Data()
        for try await byte in stream {
            guard buffer.count < 16_384 else { throw URLError(.dataLengthExceedsMaximum) }
            buffer.append(byte)
        }
        let envelope = try JSONDecoder().decode(Response.self, from: buffer)
        let address = envelope.data.ip
        guard envelope.status == "ok", IPv4Address(address) != nil || IPv6Address(address) != nil else {
            throw URLError(.cannotParseResponse)
        }
        return address
    }
}
