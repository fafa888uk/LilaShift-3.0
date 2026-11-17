// SPDX-License-Identifier: GPL-3.0-only
// Tests for AppArchiveViews (Stage 7): the archive view is reached
// from the navigation list, states its sandbox scope honestly on
// screen, never touches the sandbox escape, and runs long work in
// a cancellable detached task with real progress. No UI is needed:
// reachability and scope are properties of the source, in the
// style of DashboardV3NavigationTests / ModuleBoundaryTests.
import Foundation
import XCTest

final class AppArchiveViewsTests: XCTestCase {
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

    func testContentViewLinksToAppArchiveView() {
        let content = readSource("GestaltX/ContentView.swift")
        XCTAssertTrue(content.contains("AppArchiveView(share: presentShare)"),
                      "ContentView must navigate to AppArchiveView")
        XCTAssertTrue(content.contains("App Archive & Cache"),
                      "The navigation label must be 'App Archive & Cache'")
    }

    func testArchiveViewStatesScopeHonestly() {
        let view = readSource("GestaltX/AppArchiveViews.swift")
        XCTAssertTrue(view.contains("cannot read or delete another app's private data"),
                      "The view must state on screen that other apps' private data is out of scope")
        XCTAssertTrue(view.contains("only archives this app's own data"),
                      "The view must state that it archives only this app's own data")
    }

    func testArchiveViewNeverTouchesTheSandboxEscape() {
        let view = readSource("GestaltX/AppArchiveViews.swift")
        XCTAssertFalse(view.contains("worse_query"),
                       "The archive view must not reference worse_query")
        XCTAssertFalse(view.contains("ContainerAccess"),
                       "The archive view must not reference ContainerAccess")
        XCTAssertFalse(view.contains("SecurityEngine"),
                       "The archive view must not reference SecurityEngine")
    }

    func testArchiveViewRunsLongWorkCancellableWithProgress() {
        let view = readSource("GestaltX/AppArchiveViews.swift")
        XCTAssertTrue(view.contains("Task.detached"),
                      "Long archive/cache work must run in a detached task")
        XCTAssertTrue(view.contains("activeTask?.cancel()"),
                      "Long work must be cancellable from the view")
        XCTAssertTrue(view.contains("ProgressView(value:"),
                      "Long work must show real progress")
    }
}
