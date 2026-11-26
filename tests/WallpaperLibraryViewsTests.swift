// SPDX-License-Identifier: GPL-3.0-only
// Tests for WallpaperLibraryViews (Stage 8): the library view is
// reached from the navigation list, states the honest boundary on
// screen, never touches the sandbox escape, uses GlassTokens only,
// and the home background falls back to the default gradient when
// nothing is chosen. No UI is needed for the source properties, in
// the style of DashboardV3NavigationTests / ModuleBoundaryTests;
// the home-background fallback is a real model run.
import Foundation
import XCTest
@testable import GestaltX

final class WallpaperLibraryViewsTests: XCTestCase {
    private let fm = FileManager.default

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func readSource(_ relativePath: String) -> String {
        let url = Self.repoRoot.appendingPathComponent(relativePath)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("Cannot read \(relativePath)")
            return ""
        }
        return text
    }

    func testContentViewLinksToWallpaperLibraryView() {
        let content = readSource("GestaltX/ContentView.swift")
        XCTAssertTrue(content.contains("WallpaperLibraryView(model: wallpaperLibrary)"),
                      "ContentView must navigate to WallpaperLibraryView")
        XCTAssertTrue(content.contains("Wallpaper Library"),
                      "The navigation label must be 'Wallpaper Library'")
    }

    func testLibraryViewStatesHonestBoundary() {
        let view = readSource("GestaltX/WallpaperLibraryViews.swift")
        XCTAssertTrue(view.contains("cannot set the system wallpaper directly"),
                      "The view must state on screen that the system wallpaper cannot be set directly")
        XCTAssertTrue(view.contains("Save to Photos"),
                      "The view must offer the honest Photos export")
        XCTAssertTrue(view.contains("only changes the background inside LilaShift"),
                      "The home background must be labelled in-app only")
    }

    func testLibraryViewNeverTouchesTheSandboxEscape() {
        let view = readSource("GestaltX/WallpaperLibraryViews.swift")
        XCTAssertFalse(view.contains("worse_query"),
                       "The library view must not reference worse_query")
        XCTAssertFalse(view.contains("ContainerAccess"),
                       "The library view must not reference ContainerAccess")
        XCTAssertFalse(view.contains("SecurityEngine"),
                       "The library view must not reference SecurityEngine")
        XCTAssertFalse(view.contains("GXCustomizationAccess"),
                       "The library view must not reference the PosterBoard escape")
        let engine = readSource("GestaltX/WallpaperLibrary.swift")
        XCTAssertFalse(engine.contains("worse_query("),
                       "The library engine must not call the sandbox escape")
        XCTAssertFalse(engine.contains("ContainerAccess"),
                       "The library engine must not reference ContainerAccess")
    }

    func testLibraryViewUsesGlassTokens() {
        let view = readSource("GestaltX/WallpaperLibraryViews.swift")
        XCTAssertFalse(view.contains("Color(red:"),
                       "The library view must not define its own colors: use GlassTokens / Color.gestaltAccent")
        XCTAssertNil(view.range(of: "cornerRadius: [0-9]", options: .regularExpression),
                     "The library view must not use literal corner radii: use GlassTokens")
    }

    func testHomeBackgroundIsWired() {
        let dashboard = readSource("GestaltX/DashboardV3.swift")
        XCTAssertTrue(dashboard.contains("HomeBackgroundView(image: homeBackground.image)"),
                      "The Tools home must render through HomeBackgroundView")
        XCTAssertTrue(dashboard.contains("homeBackground.reload()"),
                      "The Tools home must reload the background when the setting changes")
        let center = readSource("GestaltX/PersonalizationCenter.swift")
        XCTAssertTrue(center.contains("homeWallpaperID"),
                      "PersonalizationSettings must carry the home background choice")
        XCTAssertTrue(center.contains("setHomeWallpaperID"),
                      "PersonalizationCenter must own the home background save")
    }

    func testHomeBackgroundModelFallsBackToDefault() async throws {
        // With no installation ID there is no setting to read, so
        // the model must fall back to the default (nil image).
        let key = "GestaltX.installationID"
        let prior = UserDefaults.standard.string(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
        defer {
            if let prior { UserDefaults.standard.set(prior, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        let storage = fm.temporaryDirectory.appendingPathComponent("GX-HomeBG-\(UUID().uuidString)")
        try fm.createDirectory(at: storage, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: storage) }
        let model = await HomeBackgroundModel(store: WallpaperLibraryStore(storage: storage))
        await model.reload()
        let image = await model.image
        XCTAssertNil(image, "No home wallpaper chosen means the default lavender gradient (nil image)")
    }

    func testDeleteHomeBackgroundEntryClearsSetting() async throws {
        // The real settings file is used here, so the prior file
        // and installation ID are backed up and restored.
        let key = "GestaltX.installationID"
        let priorID = UserDefaults.standard.string(forKey: key)
        let historyDir = RestoreIntelligence.historyDirectory
        let settingsFile = historyDir.appendingPathComponent(PersonalizationSettingsStore.fileName)
        let sidecarFile = HistoryJournal.digestURL(for: settingsFile)
        let backupDir = fm.temporaryDirectory.appendingPathComponent("GX-HomeBG-Backup-\(UUID().uuidString)")
        try fm.createDirectory(at: backupDir, withIntermediateDirectories: false)
        let backedUpSettings = fm.fileExists(atPath: settingsFile.path)
        let backedUpSidecar = fm.fileExists(atPath: sidecarFile.path)
        if backedUpSettings { try fm.copyItem(at: settingsFile, to: backupDir.appendingPathComponent(settingsFile.lastPathComponent)) }
        if backedUpSidecar { try fm.copyItem(at: sidecarFile, to: backupDir.appendingPathComponent(sidecarFile.lastPathComponent)) }
        defer {
            try? fm.removeItem(at: settingsFile)
            try? fm.removeItem(at: sidecarFile)
            if backedUpSettings { try? fm.copyItem(at: backupDir.appendingPathComponent(settingsFile.lastPathComponent), to: settingsFile) }
            if backedUpSidecar { try? fm.copyItem(at: backupDir.appendingPathComponent(sidecarFile.lastPathComponent), to: sidecarFile) }
            try? fm.removeItem(at: backupDir)
            if let priorID { UserDefaults.standard.set(priorID, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        let deviceID = "test-home-bg-\(UUID().uuidString)"
        UserDefaults.standard.set(deviceID, forKey: key)
        let storage = fm.temporaryDirectory.appendingPathComponent("GX-WallpaperLibrary-\(UUID().uuidString)")
        try fm.createDirectory(at: storage, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: storage) }
        let store = WallpaperLibraryStore(storage: storage)
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8Xw8AAwMCAO+ip1sAAAAASUVORK5CYII=")!
        let entry = try await store.importImage(png, name: "Home", category: .other)
        XCTAssertNil(PersonalizationCenter.setHomeWallpaperID(entry.id))
        XCTAssertEqual(PersonalizationCenter.loadHomeWallpaperID(), entry.id)
        let model = await WallpaperLibraryModel(store: store, exporter: WallpaperLibraryTests.FakeWallpaperPhotoExporter())
        // The view always loads before deleting (`.task`); load here
        // so the model's cached home-background id is populated.
        await model.load()
        await model.deleteEntry(entry)
        XCTAssertNil(PersonalizationCenter.loadHomeWallpaperID(),
                     "Deleting the home background wallpaper must clear the setting")
    }
}
