// SPDX-License-Identifier: GPL-3.0-only
// AppDirectories tests (Stage 3).
//
// The tests pin the relative structure only: the absolute Application
// Support path differs between simulator, device and CI.
import Foundation
import XCTest
@testable import GestaltX

final class AppDirectoriesTests: XCTestCase {
    func testStoragePaths() {
        XCTAssertTrue(AppDirectories.customizationStorage.path.hasSuffix("GestaltX/Customization"),
                      "Customization packs live under GestaltX/Customization")
        XCTAssertTrue(AppDirectories.launchImagesStorage.path.hasSuffix("GestaltX/LaunchImages"),
                      "Launch artwork lives under GestaltX/LaunchImages")
        XCTAssertTrue(AppDirectories.launchImagesCatalogStorage.path.hasSuffix("GestaltX/LaunchImages/Catalog"),
                      "The launch artwork catalog lives under GestaltX/LaunchImages/Catalog")
        XCTAssertTrue(AppDirectories.launchImagesCatalogStorage.path.hasPrefix(AppDirectories.launchImagesStorage.path),
                      "The catalog is inside the launch images directory")
        XCTAssertTrue(AppDirectories.appAppearanceDraftsStorage.path.hasSuffix("GestaltX/AppAppearance/Drafts"),
                      "App-appearance drafts live under GestaltX/AppAppearance/Drafts")
        XCTAssertTrue(AppDirectories.appArchivesStorage.path.hasSuffix("GestaltX/AppArchives"),
                      "App archives live under GestaltX/AppArchives")
        XCTAssertTrue(AppDirectories.appArchivesStorage.path.hasPrefix(AppDirectories.applicationSupport.path),
                      "App archives are inside Application Support")
        XCTAssertTrue(AppDirectories.customizationStorage.path.hasPrefix(AppDirectories.applicationSupport.path),
                      "Customization storage is inside Application Support")
    }

    func testWallpaperLibraryStoragePath() {
        XCTAssertTrue(AppDirectories.wallpaperLibraryStorage.path.hasSuffix("GestaltX/WallpaperLibrary"),
                      "The wallpaper library lives under GestaltX/WallpaperLibrary")
        XCTAssertTrue(AppDirectories.wallpaperLibraryStorage.path.hasPrefix(AppDirectories.applicationSupport.path),
                      "The wallpaper library is inside Application Support")
    }
}
