// SPDX-License-Identifier: GPL-3.0-only
// W6 registration (LilaShift 5.0.0 Wave 1, W6) — catalog metadata
// for the five file-browser features, so the coordinator can wire
// them into the app without touching `FeatureCatalog.swift` or
// `ContentView.swift`. This file only declares data: ids, Chinese
// titles, categories and which W6 view each feature opens. It
// stages, writes or reads nothing.
//
// Feature → view mapping: the batch-selection bar and the folder
// import both live in `W6FileBrowserView` (import is an action in
// the browser's menu); cross-app browsing, splash-ad paths and
// cross-app cache statistics each have their own view.
import Foundation

/// Which W6 view a feature opens. The coordinator switches on
/// this to present the view; the views themselves live in
/// `W6FileBrowserViews.swift`.
enum W6ViewKind: String, Equatable, Sendable {
    /// `W6FileBrowserView` (also hosts folder import).
    case fileBrowser
    /// `W6CrossAppBrowserView`.
    case crossAppBrowser
    /// `W6SplashAdPathsView`.
    case splashAdPaths
    /// `W6CrossAppCacheView`.
    case crossAppCache
}

/// Catalog metadata for one W6 feature: the stable id, the
/// Chinese title shown in the catalog, the existing catalog
/// category it belongs to, the view it opens, and a one-line
/// description of what it does (and does not do).
struct W6FeatureRegistration: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let category: FeatureCatalogCategory
    let viewKind: W6ViewKind
    let detail: String
}

/// The five W6 features, in task order. Ids are stable:
/// renaming one breaks the coordinator wiring and the record.
enum W6Registration {
    static let all: [W6FeatureRegistration] = [
        W6FeatureRegistration(
            id: "w6-batch-selection",
            title: "文件浏览器多选批量操作",
            category: .advancedTools,
            viewKind: .fileBrowser,
            detail: "多选文件与文件夹，全选 / 取消全选 / 反选，底部操作栏分享与打包 ZIP；不含批量删除。"),
        W6FeatureRegistration(
            id: "w6-folder-import",
            title: "导入文件夹递归复制",
            category: .advancedTools,
            viewKind: .fileBrowser,
            detail: "流式递归复制整个文件夹，重名时保留两者自动编号、覆盖或跳过；拒绝符号链接与受保护项。"),
        W6FeatureRegistration(
            id: "w6-splash-ad-paths",
            title: "开屏广告缓存路径识别",
            category: .deviceDiagnostics,
            viewKind: .splashAdPaths,
            detail: "7 个应用的开屏广告缓存路径表（可更新），逐条标注待核实；只识别，不锁死、不清理。"),
        W6FeatureRegistration(
            id: "w6-cross-app-browse",
            title: "跨应用文件浏览",
            category: .advancedTools,
            viewKind: .crossAppBrowser,
            detail: "只读浏览其他应用容器，上限 iOS 27.3 beta 1；27.3 beta 2 起底座封堵，显示版本指引。"),
        W6FeatureRegistration(
            id: "w6-cross-app-cache",
            title: "跨应用缓存占用统计",
            category: .deviceDiagnostics,
            viewKind: .crossAppCache,
            detail: "只读统计各应用 Library/Caches 与 tmp 占用及开屏广告路径字节数；不清理。"),
    ]

    static func registration(for id: String) -> W6FeatureRegistration? {
        all.first { $0.id == id }
    }
}
