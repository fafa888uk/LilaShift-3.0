// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Wave 1 workflow W4 (MG key table) feature registrations
/// (LilaShift 5.0.0).
///
/// Directory metadata only: the coordinator wires these into
/// `FeatureCatalog` and the MG field editor search. This file stages
/// nothing, writes nothing, and reads no MobileGestalt cache. It must
/// not be edited to add features from other workflows.
enum W4Registration {
    /// The existing host surface a feature belongs to. W4 adds no new
    /// page of its own: both features extend the key table the app
    /// already has.
    enum ViewKind: String, Sendable {
        /// The MobileGestalt key table / MG field editor search list
        /// (`MGKeysTableView`, driven by `MGKeysTable.matching`).
        case keyTableSearch
        /// The per-row key name shown in the key table rows.
        case keyRowDisplay
    }

    /// One W4 feature, as the coordinator's wiring table expects it.
    struct Feature: Sendable, Equatable, Identifiable {
        /// Stable id, e.g. "w4.appleWikiKeyTable".
        let id: String
        /// Simplified Chinese title shown in the catalog.
        let chineseTitle: String
        let category: FeatureCatalogCategory
        let viewKind: ViewKind
        /// One-line summary of what the feature adds.
        let summary: String
    }

    /// The two W4 features, in catalog order.
    static let features: [Feature] = [
        Feature(
            id: "w4.appleWikiKeyTable",
            chineseTitle: "Apple Wiki 键值表",
            category: .deviceDiagnostics,
            viewKind: .keyTableSearch,
            summary: "943 个 Apple Wiki 键值（人类可读名与英文描述）接入 MG 字段编辑器搜索。"),
        Feature(
            id: "w4.chineseKeyNames",
            chineseTitle: "键名中文翻译",
            category: .deviceDiagnostics,
            viewKind: .keyRowDisplay,
            summary: "122 个常用键的人工审校中文名与中文描述；冷门键显示“暂无中文名”。"),
    ]
}
