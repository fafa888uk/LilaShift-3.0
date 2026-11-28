// SPDX-License-Identifier: GPL-3.0-only
// W1 registration (LilaShift 5.0.0, Wave 1: DeviceKit) — the
// directory metadata for the five new DeviceKit diagnostics.
//
// This file ONLY declares metadata. It does not modify
// `FeatureCatalog`, `ContentView` or any other wiring: the W1
// coordinator merges these five items into the catalog and the
// diagnostics page. Until that wiring lands, the items live here
// and are covered by `DeviceDiagnosticsTests`.
//
// Every item points at the same SwiftUI view,
// `DeviceDiagnosticsCard`, and names the section inside it, so the
// coordinator can deep-link to one diagnostic without a second
// view per item.
import Foundation

/// The W1 DeviceKit directory: five read-only diagnostics, all in
/// the Diagnostics category, all shown by
/// `DeviceDiagnosticsCard`.
enum W1DeviceDiagnosticsRegistration {
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

    /// The single SwiftUI view type for all five items.
    static let viewType = "DeviceDiagnosticsCard"

    /// The five items, in audit order (screen first — the two most
    /// valuable items are screen metrics and biometrics).
    static let items: [Item] = [
        Item(
            id: "w1.screenMetrics",
            chineseTitle: "屏幕物理指标",
            englishTitle: "Screen Physical Metrics",
            category: .deviceDiagnostics,
            viewType: viewType,
            section: "screen",
            description: "PPI, screen size, aspect ratio and Display Zoom, from UIScreen and the model table."),
        Item(
            id: "w1.biometrics",
            chineseTitle: "生物识别硬件",
            englishTitle: "Biometric Hardware",
            category: .deviceDiagnostics,
            viewType: viewType,
            section: "biometrics",
            description: "Face ID / Touch ID hardware detection, from LocalAuthentication."),
        Item(
            id: "w1.lowPowerMode",
            chineseTitle: "低电量模式",
            englishTitle: "Low Power Mode",
            category: .deviceDiagnostics,
            viewType: viewType,
            section: "lowPower",
            description: "Whether Low Power Mode is on, from ProcessInfo."),
        Item(
            id: "w1.screenBrightness",
            chineseTitle: "屏幕亮度",
            englishTitle: "Screen Brightness",
            category: .deviceDiagnostics,
            viewType: viewType,
            section: "brightness",
            description: "Current screen brightness, from UIScreen."),
        Item(
            id: "w1.diskCapacity",
            chineseTitle: "可用磁盘容量",
            englishTitle: "Available Disk Space",
            category: .deviceDiagnostics,
            viewType: viewType,
            section: "disk",
            description: "Available and total disk capacity, from FileManager volume resource values."),
    ]

    /// Every item id, for validating stored orders and for the
    /// coordinator's merge (an id already in the catalog is a
    /// conflict, never a silent duplicate).
    static var allIDs: Set<String> { Set(items.map(\.id)) }
}
