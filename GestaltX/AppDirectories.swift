// SPDX-License-Identifier: GPL-3.0-only
// App-owned storage locations (Stage 3).
//
// One place for the Application Support paths the models build
// inline with FileManager today (CustomizationModel,
// LaunchArtworkCatalogModel, LaunchArtworkModel). The paths are
// byte-identical to the inline ones they replace; the views and
// models are wired to these in the commit-5 move-out, and this file
// exists now so its locations are tested before that move.
import Foundation

enum AppDirectories {
    /// The app's Application Support directory.
    static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    /// Customization packs (wallpapers, dialer skins).
    static var customizationStorage: URL {
        applicationSupport.appendingPathComponent("GestaltX/Customization", isDirectory: true)
    }

    /// Launch artwork (per-app launch images and their backups).
    static var launchImagesStorage: URL {
        applicationSupport.appendingPathComponent("GestaltX/LaunchImages", isDirectory: true)
    }

    /// The launch artwork catalog (scan results and ordering).
    static var launchImagesCatalogStorage: URL {
        applicationSupport.appendingPathComponent("GestaltX/LaunchImages/Catalog", isDirectory: true)
    }

    /// App-appearance drafts (per-app icon / wallpaper drafts).
    static var appAppearanceDraftsStorage: URL {
        applicationSupport.appendingPathComponent("GestaltX/AppAppearance/Drafts", isDirectory: true)
    }

    /// App archives (Stage 7): sandbox-compliant ZIP archives of
    /// this app's own data, plus their pre-restore archives.
    static var appArchivesStorage: URL {
        applicationSupport.appendingPathComponent("GestaltX/AppArchives", isDirectory: true)
    }
}
