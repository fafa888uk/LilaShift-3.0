// SPDX-License-Identifier: GPL-3.0-only
// W2 directory metadata (LilaShift 5.0.0, Wave 1 W2) — the two
// Pulse-inspired features (structured log viewing, log export
// sharing), as data only. This file wires nothing: it declares the
// id, Simplified Chinese title, catalog category and SwiftUI view
// type for each feature so the Wave 1 coordinator can wire them
// into `FeatureCatalog` / `ContentView` in one place. Both features
// live in `StructuredLogView`: the viewer is the log list itself,
// the export is that view's share action (which exports the
// entries currently shown, after filters).
import Foundation

/// One W2 feature's directory entry: stable id, Simplified Chinese
/// title, catalog category, and the SwiftUI view type that presents
/// it. `viewType` is the type name as a string so this metadata
/// stays data (no view is constructed here).
struct W2FeatureMetadata: Equatable, Sendable {
    let id: String
    let title: String
    let category: FeatureCatalogCategory
    let viewType: String
}

enum W2Registration {
    /// Both W2 features are diagnostics: they present the operation
    /// log, the same category as the Diagnostics Expansion page.
    static let category = FeatureCatalogCategory.deviceDiagnostics

    static let features: [W2FeatureMetadata] = [
        W2FeatureMetadata(
            id: "w2.structured-log-viewer",
            title: "结构化日志查看",
            category: category,
            viewType: "StructuredLogView"),
        W2FeatureMetadata(
            id: "w2.log-export-share",
            title: "日志导出分享",
            category: category,
            viewType: "StructuredLogView"),
    ]

    static func feature(id: String) -> W2FeatureMetadata? {
        features.first { feature in feature.id == id }
    }
}
