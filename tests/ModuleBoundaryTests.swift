// SPDX-License-Identifier: GPL-3.0-only
// Module boundary tests (Stage 3, ADR-2-04; Stage 5 adds the
// backup/restore/security boundaries, ADR-2-05 / ADR-2-08; Stage 6
// adds the diagnostics boundaries, ADR-2-09; Stage 7 adds the
// archive/cache boundaries, ADR-2-10).
//
// The Stage 2 boundaries as executable rules, read straight from the
// checked-out sources (this target runs with a host app in the same
// checkout, so #filePath resolves to the repo): views do no file I/O
// and never call SafePatch.simulate directly, design tokens live in
// exactly one place, and no force-try hides a failure.
import Foundation
import XCTest

final class ModuleBoundaryTests: XCTestCase {
    /// The repo root: this file lives in <repo>/tests/.
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func readSource(_ relativePath: String, file: StaticString = #filePath, line: UInt = #line) -> String {
        let url = Self.repoRoot.appendingPathComponent(relativePath)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("Cannot read \(relativePath)", file: file, line: line)
            return ""
        }
        return text
    }

    /// Source with full-line comments removed, so a doc comment
    /// naming an engine does not count as a reference to it — only
    /// code counts. Same rule as testWorseQueryCallSitesAreKnown,
    /// which matches call syntax ("worse_query("), not mentions.
    private func codeText(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func swiftFiles(in relativeDirectory: String) -> [URL] {
        let directory = Self.repoRoot.appendingPathComponent(relativeDirectory)
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "swift" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func viewFiles() -> [URL] {
        swiftFiles(in: "GestaltX").filter { $0.lastPathComponent.hasSuffix("Views.swift") }
    }

    func testViewsDoNotTouchTheSandboxEscape() {
        for file in viewFiles() {
            let text = readSource("GestaltX/" + file.lastPathComponent)
            XCTAssertFalse(text.contains("worse_query"),
                           "\(file.lastPathComponent) must not reference worse_query: only the engine (ContainerAccess) may")
        }
    }

    func testWorseQueryCallSitesAreKnown() {
        // The sandbox-escape choke point (ADR-2-05): only these files
        // may call worse_query / worse_query_release. A doc comment
        // mentioning worse_query does not count — only the call syntax.
        // Stage 4 adds no call site (the sentinel only names the
        // mechanism in comments).
        let knownCallers: Set<String> = [
            "ContainerAccess.swift", "GestaltManager.swift", "SystemSettingsView.swift",
            "CustomizationStore.swift", "LaunchArtworkStore.swift", "AppSoundStore.swift",
        ]
        // AppSoundStore belongs here: it follows the LaunchArtworkStore
        // pattern exactly — acquire through GXCustomizationAccess (the
        // single choke point) and release the lease handle. It adds no
        // new escape entry point.
        var callers: Set<String> = []
        for file in swiftFiles(in: "GestaltX") {
            let text = readSource("GestaltX/" + file.lastPathComponent)
            if text.contains("worse_query(") || text.contains("worse_query_release(") {
                callers.insert(file.lastPathComponent)
            }
        }
        XCTAssertEqual(callers, knownCallers,
                       "A new worse_query call site appeared — the escape has exactly one choke point")
    }

    func testViewsDoNotCallWritersOrContainerAccess() {
        for file in viewFiles() {
            let text = readSource("GestaltX/" + file.lastPathComponent)
            XCTAssertFalse(text.contains("DevicePlistWriter"),
                           "\(file.lastPathComponent) must not reference DevicePlistWriter")
            XCTAssertFalse(text.contains("ContainerAccess"),
                           "\(file.lastPathComponent) must not reference ContainerAccess")
        }
    }

    func testViewsDoNotReadFilesDirectly() {
        for file in viewFiles() {
            let text = readSource("GestaltX/" + file.lastPathComponent)
            XCTAssertFalse(text.contains("Data(contentsOf"),
                           "\(file.lastPathComponent) must not read files with Data(contentsOf:)")
            XCTAssertFalse(text.contains("String(contentsOf"),
                           "\(file.lastPathComponent) must not read files with String(contentsOf:)")
            XCTAssertFalse(text.contains("FileManager."),
                           "\(file.lastPathComponent) must not touch the file system: use an engine or AppDirectories")
        }
    }

    func testHeroTintLivesOnlyInGlassTokens() {
        for file in swiftFiles(in: "GestaltX") {
            let text = readSource("GestaltX/" + file.lastPathComponent)
            XCTAssertFalse(text.contains("private var heroTint"),
                           "\(file.lastPathComponent) must not define its own heroTint: use GlassTokens.heroTint")
        }
    }

    // MARK: - Stage 8 boundaries (TASKBOOK §7)

    func testWallpaperLibraryNeverLeavesItsSandbox() {
        // TASKBOOK §7.3 / ADR-2-10: the library covers this app's
        // own images only. The engine and its view must never name
        // the sandbox escape, the container accessor, the
        // cross-container gate, or the PosterBoard escape — not even
        // in a comment, so a future "just one more root" cannot
        // sneak in unnoticed. The store's only storage root is
        // AppDirectories.wallpaperLibraryStorage.
        for file in ["GestaltX/WallpaperLibrary.swift", "GestaltX/WallpaperLibraryViews.swift"] {
            let text = readSource(file)
            for forbidden in ["worse_query", "ContainerAccess", "SecurityEngine", "GXCustomizationAccess"] {
                XCTAssertFalse(text.contains(forbidden),
                               "\(file) must not reference \(forbidden): the library is this app's own images only")
            }
        }
        let engine = readSource("GestaltX/WallpaperLibrary.swift")
        XCTAssertFalse(engine.contains("appendingPathComponent(\"GestaltX/"),
                       "The library engine must not build its own GestaltX paths: storage comes from AppDirectories")
        let view = readSource("GestaltX/WallpaperLibraryViews.swift")
        XCTAssertTrue(view.contains("AppDirectories.wallpaperLibraryStorage"),
                      "The library model must root at AppDirectories.wallpaperLibraryStorage")
    }

    func testWallpaperLibraryHonestBoundary() {
        // TASKBOOK §7.3: no code path may claim to set the system
        // wallpaper. The honest copy must be present in the view.
        for file in ["GestaltX/WallpaperLibrary.swift", "GestaltX/WallpaperLibraryViews.swift"] {
            let text = readSource(file)
            XCTAssertFalse(text.contains("setSystemWallpaper"),
                           "\(file) must not name a system-wallpaper setter: no public API does that")
            XCTAssertFalse(text.contains("Set as Wallpaper"),
                           "\(file) must not offer 'Set as Wallpaper': only 'Save to Photos'")
        }
        let view = readSource("GestaltX/WallpaperLibraryViews.swift")
        XCTAssertTrue(view.contains("cannot set the system wallpaper directly"),
                      "The library view must state the honest boundary on screen")
        XCTAssertTrue(view.contains("only changes the background inside LilaShift"),
                      "The home background must be labelled in-app only")
    }

    func testNewViewsUseGlassTokens() {
        // Stage 8, TASKBOOK §8.1: the new views take every color,
        // radius and spacing from GlassTokens — no ad-hoc literals.
        let view = readSource("GestaltX/WallpaperLibraryViews.swift")
        XCTAssertFalse(view.contains("Color(red:"),
                       "The library view must not define its own colors: use GlassTokens / Color.gestaltAccent")
        XCTAssertNil(view.range(of: "cornerRadius: [0-9]", options: .regularExpression),
                     "The library view must not use literal corner radii: use GlassTokens")
    }

    func testHomeWallpaperSettingIsReal() {
        // TASKBOOK §7.3: the home background choice is a real
        // persisted setting (PersonalizationSettings.homeWallpaperID),
        // and the Tools home renders through HomeBackgroundView.
        let center = readSource("GestaltX/PersonalizationCenter.swift")
        XCTAssertTrue(center.contains("homeWallpaperID"),
                      "PersonalizationSettings must carry the home background choice")
        let dashboard = readSource("GestaltX/DashboardV3.swift")
        XCTAssertTrue(dashboard.contains("HomeBackgroundView(image: homeBackground.image)"),
                      "The Tools home must render through HomeBackgroundView")
    }

    func testNoForceTry() {
        for directory in ["GestaltX", "tests"] {
            for file in swiftFiles(in: directory) {
                let text = readSource(directory + "/" + file.lastPathComponent)
                XCTAssertNil(text.range(of: "\\btry!", options: .regularExpression),
                             "\(file.lastPathComponent) must not use force-try")
            }
        }
    }

    func testSafePatchSimulateCallersAreKnown() {
        // Direct SafePatch.simulate calls are allowed only in the two
        // engine callers and the three views Stage 6 converges. This
        // test forbids NEW direct calls; it does not bless the three
        // views — Stage 6 removes them.
        let allowed: Set<String> = [
            "HomeDiagnosticsCache.swift", "PresetCatalog.swift",
            "SafePatchViews.swift", "SmartFaultDiagnosisViews.swift",
            "SystemHealthScoreViews.swift",
        ]
        var callers: Set<String> = []
        for file in swiftFiles(in: "GestaltX") {
            let text = readSource("GestaltX/" + file.lastPathComponent)
            if text.contains("SafePatch.simulate(") {
                callers.insert(file.lastPathComponent)
            }
        }
        XCTAssertEqual(callers, allowed,
                       "SafePatch.simulate callers changed: \(callers.sorted())")
    }

    func testLayoutCycleIsBroken() {
        // ADR-2-11 (Stage 4): layout resolution is a pure function
        // over raw bytes (`LayoutResolver`), so the layout type must
        // not reference `GestaltDocument` at all, and no code may
        // call the removed document-taking API.
        let layoutText = readSource("GestaltX/MobileGestaltCacheLayout.swift")
        XCTAssertFalse(layoutText.contains("GestaltDocument"),
                       "MobileGestaltCacheLayout must not reference GestaltDocument: the ADR-2-11 cycle is back")
        for directory in ["GestaltX", "tests"] {
            // This file itself holds the forbidden strings as
            // assertion literals, so it is excluded from its own
            // scan; every other file is checked.
            for file in swiftFiles(in: directory) where file.lastPathComponent != "ModuleBoundaryTests.swift" {
                let text = readSource(directory + "/" + file.lastPathComponent)
                XCTAssertFalse(text.contains("MobileGestaltCacheLayout.resolve(in:"),
                               "\(file.lastPathComponent) must resolve layouts via LayoutResolver, not MobileGestaltCacheLayout.resolve(in:)")
                XCTAssertFalse(text.contains("MobileGestaltCacheLayout.lockReason(in:"),
                               "\(file.lastPathComponent) must ask LayoutResolver for the lock reason")
                XCTAssertFalse(text.contains("layout.matches("),
                               "\(file.lastPathComponent) must match layouts via LayoutResolver.matches, not a layout method")
                XCTAssertFalse(text.contains("originalProfile.matches("),
                               "\(file.lastPathComponent) must match layouts via LayoutResolver.matches, not a layout method")
            }
        }
    }

    // MARK: - Stage 5 boundaries (ADR-2-05 / ADR-2-08)

    func testSHA256HasOneImplementation() {
        // ADR-2-08: BackupEngine owns the only SHA-256
        // implementation; every other digest call delegates to it,
        // so two call sites can never disagree. This file holds the
        // literal as an assertion, so it is excluded from its own
        // scan.
        var implementers: Set<String> = []
        for directory in ["GestaltX", "tests"] {
            for file in swiftFiles(in: directory) where file.lastPathComponent != "ModuleBoundaryTests.swift" {
                let text = readSource(directory + "/" + file.lastPathComponent)
                if text.contains("SHA256.hash(") { implementers.insert(file.lastPathComponent) }
            }
        }
        XCTAssertEqual(implementers, ["BackupEngine.swift"],
                       "SHA-256 must be implemented in exactly one place (BackupEngine): \(implementers.sorted())")
    }

    func testDevicePlistWriterHasOneAppCaller() {
        // §3.4: the device file is written only through
        // GestaltFileStore.commit (the write choke point); the
        // writer's own tests are the only other callers.
        var appCallers: Set<String> = []
        for file in swiftFiles(in: "GestaltX") {
            let text = readSource("GestaltX/" + file.lastPathComponent)
            if text.contains("DevicePlistWriter.write(") { appCallers.insert(file.lastPathComponent) }
        }
        XCTAssertEqual(appCallers, ["GestaltDocument.swift"],
                       "DevicePlistWriter must be called only from GestaltFileStore.commit: \(appCallers.sorted())")
    }

    func testAllowlistGateLivesInCommit() {
        // §3.4: the SecurityEngine allowlist gate runs inside
        // commit, nowhere else in app code (tests may call it).
        var appCallers: Set<String> = []
        for file in swiftFiles(in: "GestaltX") {
            let text = readSource("GestaltX/" + file.lastPathComponent)
            if text.contains("authorizeWrite(") && !text.contains("func authorizeWrite(") {
                appCallers.insert(file.lastPathComponent)
            }
        }
        XCTAssertEqual(appCallers, ["GestaltDocument.swift"],
                       "The allowlist gate must run in commit only: \(appCallers.sorted())")
    }

    func testViewsDoNotCallStage5Engines() {
        // The backup/restore/security engines are AppCore/manager
        // only; views go through the manager. Comments naming an
        // engine (e.g. a restore report's section header) do not
        // count — only code references.
        for file in viewFiles() {
            let text = codeText(readSource("GestaltX/" + file.lastPathComponent))
            for engine in ["BackupEngine", "RestoreEngine", "SecurityEngine"] {
                XCTAssertFalse(text.contains(engine),
                               "\(file.lastPathComponent) must not reference \(engine): engines are manager-only")
            }
        }
    }

    func testFingerprintNeverStoresPlaintextUDID() {
        // Audit R-4: the fingerprint stores the SHA-256 of the UDID,
        // never the UDID. The capture hashes it; the old plaintext
        // assignment must not come back.
        let text = readSource("GestaltX/DeviceFingerprint.swift")
        XCTAssertTrue(text.contains("BackupEngine.sha256Hex(of: Data(udid.utf8))"),
                      "Fingerprint capture must hash the UDID")
        XCTAssertFalse(text.contains("deviceID: document.extra[\"UniqueDeviceID\"]"),
                       "The fingerprint must never store the plaintext UDID again")
    }

    // MARK: - Stage 6 boundaries (ADR-2-09)

    func testDiagnosticsEngineIsPure() {
        // ADR-2-09: the engine is a pure DiagnosticsInput ->
        // DiagnosticsReport function. No UI framework, no manager,
        // no file store, no live probe — value snapshots only.
        // Comments naming a forbidden type (e.g. a doc comment
        // mentioning the manager) do not count — only code does.
        let text = codeText(readSource("GestaltX/DiagnosticsEngine.swift"))
        XCTAssertFalse(text.contains("import SwiftUI"), "DiagnosticsEngine must not import SwiftUI")
        XCTAssertFalse(text.contains("import UIKit"), "DiagnosticsEngine must not import UIKit")
        for forbidden in ["GestaltManager", "GestaltFileStore", "LiveGestaltProbe",
                          "MGCopyAnswer", "DeviceBoundPlist"] {
            XCTAssertFalse(text.contains(forbidden),
                           "DiagnosticsEngine must not reference \(forbidden): pure input only")
        }
        let exportText = codeText(readSource("GestaltX/DeidentifiedExport.swift"))
        XCTAssertFalse(exportText.contains("import SwiftUI"), "DeidentifiedExport must not import SwiftUI")
        XCTAssertFalse(exportText.contains("GestaltManager"), "DeidentifiedExport must not reference the manager")
    }

    func testViewsDoNotCallStage6Engines() {
        // The diagnostics engine and the de-identified export are
        // manager/cache only; views go through the manager (the
        // centre view calls model.diagnosticsReport, the export
        // alerts call model.export*Deidentified).
        var callers: Set<String> = []
        for file in swiftFiles(in: "GestaltX") {
            let text = readSource("GestaltX/" + file.lastPathComponent)
            if text.contains("DiagnosticsEngine.report(") || text.contains("DeidentifiedExport.strip(") {
                callers.insert(file.lastPathComponent)
            }
        }
        XCTAssertEqual(callers, ["GestaltManager.swift", "HomeDiagnosticsCache.swift"],
                       "Only the manager and the home cache may run the diagnostics engine or strip an export: \(callers.sorted())")
        for file in viewFiles() {
            let text = readSource("GestaltX/" + file.lastPathComponent)
            XCTAssertFalse(text.contains("DiagnosticsEngine"),
                           "\(file.lastPathComponent) must not reference DiagnosticsEngine: views go through the manager")
            XCTAssertFalse(text.contains("DeidentifiedExport"),
                           "\(file.lastPathComponent) must not reference DeidentifiedExport: views go through the manager")
        }
    }

    func testDiagnosticsReportIsRedactedAtConstruction() {
        // ADR-2-06: identity is redacted when a finding is built,
        // never at display time. The engine's only evidence path
        // runs through LilaLog.redact (the redactor in
        // LoggingEngine.swift).
        let text = readSource("GestaltX/DiagnosticsEngine.swift")
        XCTAssertTrue(text.contains("LilaLog.redact"),
                      "DiagnosticsEngine must redact evidence through LilaLog.redact")
        XCTAssertFalse(text.contains("UniqueDeviceID"),
                       "DiagnosticsEngine must never name a device-identity key in its own source")
    }

    // MARK: - Stage 7 boundaries (ADR-2-10)

    func testAppArchiveEngineNeverTouchesOtherAppsContainers() {
        // ADR-2-10 / TASKBOOK §6.2: archives cover this app's own
        // data only. The engine and its view must never name the
        // sandbox escape, the container accessor, the cross-container
        // gate, or a device-identity key — not even in a comment, so
        // a future "just one more root" cannot sneak in unnoticed.
        for file in ["GestaltX/AppArchiveEngine.swift", "GestaltX/AppArchiveViews.swift"] {
            let text = readSource(file)
            for forbidden in ["worse_query", "ContainerAccess", "SecurityEngine", "UniqueDeviceID"] {
                XCTAssertFalse(text.contains(forbidden),
                               "\(file) must not reference \(forbidden): archives are this app's own data only")
            }
        }
    }

    func testCacheDeletionOnlyTouchesTrackedItems() {
        // TASKBOOK §6.3: deletion only ever touches entries this
        // module produced. The delete path must check deletability
        // first and must refuse protected entries by listing them as
        // skipped, never by silently dropping them.
        let text = readSource("GestaltX/CacheAnalysis.swift")
        XCTAssertTrue(text.contains("isDeletableFile(atPath:"),
                      "CacheAnalyzer must check deletability before removing a file")
        XCTAssertTrue(text.contains("skippedProtected.append"),
                      "CacheAnalyzer must list refused protected entries as skipped")
        XCTAssertTrue(text.contains("CustomizationFiles.checked("),
                      "CacheAnalyzer must resolve every deletion through the checked-path helper")
    }

    func testCacheMeasurementHasOneImplementation() {
        // DATA_MODELS §4.3: the cache measurement lives in exactly
        // one place (CacheAnalyzer). The old measurer delegates; it
        // must not keep its own enumeration loop.
        let text = readSource("GestaltX/DiagnosticsExpansion.swift")
        XCTAssertFalse(text.contains("enumerator("),
                       "DiagnosticsExpansion must not enumerate directories itself: CacheAnalyzer owns measurement")
        XCTAssertTrue(text.contains("CacheAnalyzer.analyze("),
                      "AppContainerCacheMeasurer must delegate measurement to CacheAnalyzer")
        XCTAssertTrue(text.contains("CacheAnalyzer.clearCaches("),
                      "AppContainerCacheMeasurer must delegate clearing to CacheAnalyzer")
    }

    func testSeverityHasExactlyOneSortOrder() {
        // Stage 6 shipped `Severity.sortOrder` twice with opposite
        // orderings (error 0 in DiagnosticsEngine, error 2 in the
        // centre view's extension) — an invalid redeclaration that
        // fails compilation, in the same class as the Stage 4
        // `cacheData` triplication. Exactly one definition may
        // exist, and it must be the engine's (error first when
        // sorted ascending).
        let engine = readSource("GestaltX/DiagnosticsEngine.swift")
        let view = readSource("GestaltX/DiagnosticsCentreView.swift")
        let definitions = engine.components(separatedBy: "var sortOrder").count - 1
            + view.components(separatedBy: "var sortOrder").count - 1
        XCTAssertEqual(definitions, 1, "Severity.sortOrder must be defined exactly once")
        XCTAssertTrue(engine.contains("case .error: return 0"),
                      "The single sortOrder must order error first (error 0)")
        XCTAssertFalse(view.contains("var sortOrder"),
                       "The centre view must not redeclare sortOrder")
    }
}
