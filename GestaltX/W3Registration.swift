// SPDX-License-Identifier: GPL-3.0-only
// W3 registration (LilaShift 5.0.0, Wave 1 — IPA security audit).
//
// Directory metadata for the six W3 features. This file is the
// ONLY wiring this workflow adds: it does not touch
// `FeatureCatalog.swift`, `ContentView.swift`, `project.pbxproj`
// or any workflow file. The Wave 1 coordinator wires these
// entries into the catalog / navigation later; until then the
// audit page is reachable only through `IPAAuditView` directly.
//
// All six features live on the one audit page (`IPAAuditView`):
// the page imports the IPA, runs the whole pipeline, and shows
// every result. The `viewKind` therefore names the same view for
// all six entries, and the coordinator can group them under one
// destination.
import Foundation

/// Which SwiftUI view hosts a W3 feature. Stored as the view
/// type's name so the coordinator can resolve it without this
/// file importing view types.
enum W3RegistrationViewKind: String, Equatable, Sendable {
    case ipaAudit = "IPAAuditView"
}

/// One W3 feature's directory entry.
struct W3FeatureRegistration: Equatable, Sendable {
    /// Stable ID, e.g. "w3.macho".
    let id: String
    /// Simplified Chinese title shown in the directory.
    let title: String
    /// The existing feature category this entry belongs under.
    let category: FeatureCatalogCategory
    /// The view that hosts the feature.
    let viewKind: W3RegistrationViewKind
}

enum W3Registration {
    /// The six W3 features, in task order.
    static let features: [W3FeatureRegistration] = [
        W3FeatureRegistration(
            id: "w3.macho",
            title: "Mach-O 解析",
            category: .deviceDiagnostics,
            viewKind: .ipaAudit),
        W3FeatureRegistration(
            id: "w3.csblob",
            title: "双槽签名解析",
            category: .deviceDiagnostics,
            viewKind: .ipaAudit),
        W3FeatureRegistration(
            id: "w3.ipa-scan",
            title: "IPA 安全拆包审查",
            category: .deviceDiagnostics,
            viewKind: .ipaAudit),
        W3FeatureRegistration(
            id: "w3.threat-catalog",
            title: "威胁特征库与四级裁决",
            category: .deviceDiagnostics,
            viewKind: .ipaAudit),
        W3FeatureRegistration(
            id: "w3.cve-radar",
            title: "CVE 雷达",
            category: .deviceDiagnostics,
            viewKind: .ipaAudit),
        W3FeatureRegistration(
            id: "w3.report-export",
            title: "审计报告导出",
            category: .deviceDiagnostics,
            viewKind: .ipaAudit),
    ]
}
