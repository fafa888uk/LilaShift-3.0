// SPDX-License-Identifier: GPL-3.0-only
// Module boundary tests (Stage 3, ADR-2-04).
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
}
