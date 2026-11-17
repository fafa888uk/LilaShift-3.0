// SPDX-License-Identifier: GPL-3.0-only
// Module boundary tests (Stage 3, ADR-2-04; Stage 5 adds the
// backup/restore/security boundaries, ADR-2-05 / ADR-2-08).
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
            "CustomizationStore.swift", "LaunchArtworkStore.swift",
        ]
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
        // only; views go through the manager.
        for file in viewFiles() {
            let text = readSource("GestaltX/" + file.lastPathComponent)
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
}
