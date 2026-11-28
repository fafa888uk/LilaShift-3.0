// SPDX-License-Identifier: GPL-3.0-only
// W5 registration (LilaShift 5.0.0, Wave 1: ip-tools) — the
// directory metadata for the three new network-probe tools.
//
// This file ONLY declares metadata. It does not modify
// `FeatureCatalog`, `ContentView` or any other wiring: the
// coordinator merges these three items into the catalog and the
// diagnostics page. Until that wiring lands, the items live here
// and are covered by `W5NetworkProbeTests`.
//
// Every item points at the same SwiftUI view,
// `NetworkProbeCard`, and names the section inside it, so the
// coordinator can deep-link to one tool without a second view
// per item.
import Foundation

/// The W5 network-probe directory: ping, traceroute and egress
/// ASN / BGP, all in the Diagnostics category, all shown by
/// `NetworkProbeCard`.
enum W5NetworkProbeRegistration {
    /// One directory entry: the stable id, the Chinese title shown
    /// in the catalog, the English title, the catalog category, the
    /// SwiftUI view type that renders it, and the section inside
    /// that view.
    struct Item: Equatable, Sendable {
        let id: String
        let chineseTitle: String
        let englishTitle: String
        let category: FeatureCatalogCategory
        let viewType: String
        let section: String
        let description: String
    }

    /// The single SwiftUI view type for all three items.
    static let viewType = "NetworkProbeCard"

    /// The three items, in audit order (ping first — the most
    /// valuable item — then traceroute, then egress ASN/BGP).
    static let items: [Item] = [
        Item(
            id: "w5.ping",
            chineseTitle: "Ping 测速",
            englishTitle: "Ping",
            category: .deviceDiagnostics,
            viewType: viewType,
            section: "ping",
            description: "ICMP echo round-trip time to a host or IP: min / avg / max, jitter and packet loss, from an unprivileged ICMP socket."),
        Item(
            id: "w5.traceroute",
            chineseTitle: "路由追踪",
            englishTitle: "Traceroute",
            category: .deviceDiagnostics,
            viewType: viewType,
            section: "trace",
            description: "Hop-by-hop path discovery with per-hop latency, over the same unprivileged ICMP socket."),
        Item(
            id: "w5.asnBgp",
            chineseTitle: "出口 ASN / BGP",
            englishTitle: "Egress ASN / BGP",
            category: .deviceDiagnostics,
            viewType: viewType,
            section: "asn",
            description: "The public IP and the ASN announcing it, from the RIPEstat Data API. Online only; offline it shows only local measurements."),
    ]

    /// Every item id, for validating stored orders and for the
    /// coordinator's merge (an id already in the catalog is a
    /// conflict, never a silent duplicate).
    static var allIDs: Set<String> { Set(items.map(\.id)) }
}
