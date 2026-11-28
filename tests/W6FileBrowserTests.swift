// SPDX-License-Identifier: GPL-3.0-only
// W6 file browser tests (LilaShift 5.0.0 Wave 1, W6): multi-select
// state, recursive folder import (conflicts, symlinks, SQLite
// companions, streaming copy), batch ZIP, the splash-ad path
// table (counts, verification state, JSON round-trip, real
// container matching), the cross-app version sentinel gate, and
// the W6 registration metadata. All fixtures are temporary
// directories on disk; no device and no container access needed.
import Foundation
import XCTest
import ZIPFoundation
@testable import GestaltX

final class W6FileBrowserTests: XCTestCase {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func write(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url)
    }

    // MARK: - Listing and measurement

    func testListReadsRealDirectory() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try write("hello", to: dir.appendingPathComponent("note.txt"))
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Sub"), withIntermediateDirectories: false)
        let entries = W6FileBrowser.list(root: dir)
        XCTAssertEqual(entries.map(\.name), ["Sub", "note.txt"])
        XCTAssertTrue(entries[0].isDirectory)
        XCTAssertFalse(entries[1].isDirectory)
        XCTAssertEqual(entries[1].byteCount, 5)
    }

    func testListRefusesTraversal() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertTrue(W6FileBrowser.list(root: dir, relativePath: "..").isEmpty)
        XCTAssertTrue(W6FileBrowser.list(root: dir, relativePath: "/etc").isEmpty)
        XCTAssertTrue(W6FileBrowser.list(root: dir, relativePath: "a//b").isEmpty)
    }

    func testMeasureDirectoryCountsRealBytes() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try write("12345", to: dir.appendingPathComponent("a.txt"))
        let sub = dir.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: false)
        try write("12", to: sub.appendingPathComponent("b.txt"))
        let measured = W6FileBrowser.measureDirectory(dir)
        XCTAssertTrue(measured.reachable)
        XCTAssertFalse(measured.truncated)
        XCTAssertEqual(measured.byteCount, 7)
        XCTAssertEqual(measured.fileCount, 2)
    }

    func testMeasureMissingDirectoryIsUnreachable() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let measured = W6FileBrowser.measureDirectory(missing)
        XCTAssertFalse(measured.reachable)
        XCTAssertEqual(measured.byteCount, 0)
    }

    // MARK: - Multi-select (feature 1)

    private func sampleEntries() -> [W6FileEntry] {
        [
            W6FileEntry(id: "/tmp/a.txt", name: "a.txt", isDirectory: false, byteCount: 10, modifiedAt: nil),
            W6FileEntry(id: "/tmp/b.txt", name: "b.txt", isDirectory: false, byteCount: 20, modifiedAt: nil),
            W6FileEntry(id: "/tmp/sub", name: "sub", isDirectory: true, byteCount: 0, modifiedAt: nil),
        ]
    }

    func testSelectionToggleSelectAllInvertAndPrune() {
        var selection = W6FileSelection()
        let entries = sampleEntries()
        XCTAssertTrue(selection.isEmpty)
        selection.toggle(entries[0])
        XCTAssertEqual(selection.count, 1)
        selection.toggle(entries[0])
        XCTAssertEqual(selection.count, 0)
        selection.selectAll(in: entries)
        XCTAssertEqual(selection.count, 3)
        selection.invert(in: entries)
        XCTAssertEqual(selection.count, 0)
        selection.selectAll(in: entries)
        selection.deselectAll()
        XCTAssertTrue(selection.isEmpty)
        selection.selectAll(in: entries)
        selection.prune(to: Array(entries.prefix(1)))
        XCTAssertEqual(selection.count, 1)
        XCTAssertTrue(selection.contains(entries[0]))
    }

    func testSelectionSummaryCountsFilesOnly() {
        var selection = W6FileSelection()
        let entries = sampleEntries()
        selection.selectAll(in: entries)
        let summary = selection.summary(for: entries)
        XCTAssertEqual(summary.count, 3)
        XCTAssertEqual(summary.fileCount, 2)
        XCTAssertEqual(summary.directoryCount, 1)
        XCTAssertEqual(summary.fileBytes, 30)
    }

    // MARK: - Folder import (feature 2)

    func testCopyFolderRecursesAndPreservesBytes() throws {
        let source = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: source) }
        let destinationParent = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: destinationParent) }
        try write("root", to: source.appendingPathComponent("root.txt"))
        let sub = source.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: false)
        try write("nested", to: sub.appendingPathComponent("nested.txt"))
        let result = W6FolderImport.copyFolder(source: source, into: destinationParent)
        XCTAssertTrue(result.failed.isEmpty, "failures: \(result.failed)")
        XCTAssertEqual(result.copiedFiles, 2)
        XCTAssertEqual(result.copiedBytes, 10)
        let copiedRoot = destinationParent
            .appendingPathComponent(source.lastPathComponent)
            .appendingPathComponent("root.txt")
        XCTAssertEqual(try Data(contentsOf: copiedRoot), Data("root".utf8))
        let copiedNested = destinationParent
            .appendingPathComponent(source.lastPathComponent)
            .appendingPathComponent("sub/nested.txt")
        XCTAssertEqual(try Data(contentsOf: copiedNested), Data("nested".utf8))
    }

    func testCopyFileKeepBothNumbersTheName() throws {
        let source = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: source) }
        let destinationParent = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: destinationParent) }
        let file = source.appendingPathComponent("Report.pdf")
        try write("new", to: file)
        try write("old", to: destinationParent.appendingPathComponent("Report.pdf"))
        let result = W6FolderImport.copyFile(
            source: file, into: destinationParent, conflictPolicy: .keepBoth)
        XCTAssertTrue(result.failed.isEmpty, "failures: \(result.failed)")
        XCTAssertEqual(try Data(contentsOf: destinationParent.appendingPathComponent("Report.pdf")), Data("old".utf8))
        XCTAssertEqual(try Data(contentsOf: destinationParent.appendingPathComponent("Report 2.pdf")), Data("new".utf8))
    }

    func testCopyFolderKeepBothRenamesTopFolder() throws {
        let source = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: source) }
        let destinationParent = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: destinationParent) }
        try write("new", to: source.appendingPathComponent("Report.pdf"))
        let existing = destinationParent.appendingPathComponent(source.lastPathComponent, isDirectory: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        try write("old", to: existing.appendingPathComponent("Report.pdf"))
        let result = W6FolderImport.copyFolder(
            source: source, into: destinationParent, conflictPolicy: .keepBoth)
        XCTAssertTrue(result.failed.isEmpty, "failures: \(result.failed)")
        // The top folder itself is auto-numbered, so the original
        // folder is untouched and the import lands beside it.
        XCTAssertEqual(try Data(contentsOf: existing.appendingPathComponent("Report.pdf")), Data("old".utf8))
        let renamed = destinationParent.appendingPathComponent(source.lastPathComponent + " 2")
        XCTAssertEqual(try Data(contentsOf: renamed.appendingPathComponent("Report.pdf")), Data("new".utf8))
    }

    func testCopyFolderReplaceAndSkipPolicies() throws {
        let source = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: source) }
        let destinationParent = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: destinationParent) }
        try write("new", to: source.appendingPathComponent("a.txt"))
        let target = destinationParent.appendingPathComponent(source.lastPathComponent, isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try write("old", to: target.appendingPathComponent("a.txt"))

        let replaced = W6FolderImport.copyFolder(
            source: source, into: destinationParent, conflictPolicy: .replace)
        XCTAssertTrue(replaced.failed.isEmpty, "failures: \(replaced.failed)")
        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("a.txt")), Data("new".utf8))

        try write("old2", to: target.appendingPathComponent("a.txt"))
        let skipped = W6FolderImport.copyFolder(
            source: source, into: destinationParent, conflictPolicy: .skip)
        XCTAssertTrue(skipped.failed.isEmpty, "failures: \(skipped.failed)")
        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("a.txt")), Data("old2".utf8))
        XCTAssertTrue(skipped.skipped.contains(source.path))
    }

    func testCopyFolderRefusesImportIntoItself() throws {
        let source = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: source) }
        let result = W6FolderImport.copyFolder(source: source, into: source)
        XCTAssertTrue(result.copied.isEmpty)
        XCTAssertEqual(result.failed.count, 1)
    }

    func testCopyFolderSkipsSymlinks() throws {
        let source = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: source) }
        let destinationParent = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: destinationParent) }
        let real = source.appendingPathComponent("real.txt")
        try write("real", to: real)
        try FileManager.default.createSymbolicLink(
            at: source.appendingPathComponent("link.txt"), withDestinationURL: real)
        let result = W6FolderImport.copyFolder(source: source, into: destinationParent)
        XCTAssertEqual(result.copiedFiles, 1)
        XCTAssertTrue(result.skipped.contains("link.txt"))
        let target = destinationParent
            .appendingPathComponent(source.lastPathComponent)
            .appendingPathComponent("link.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }

    func testCopyFileCarriesSQLiteCompanions() throws {
        let source = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: source) }
        let destinationParent = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: destinationParent) }
        let db = source.appendingPathComponent("cache.db")
        try write("db", to: db)
        try write("wal", to: source.appendingPathComponent("cache.db-wal"))
        try write("shm", to: source.appendingPathComponent("cache.db-shm"))
        let result = W6FolderImport.copyFile(source: db, into: destinationParent)
        XCTAssertTrue(result.failed.isEmpty, "failures: \(result.failed)")
        XCTAssertEqual(result.copiedFiles, 3)
        XCTAssertEqual(try Data(contentsOf: destinationParent.appendingPathComponent("cache.db-wal")), Data("wal".utf8))
        XCTAssertEqual(try Data(contentsOf: destinationParent.appendingPathComponent("cache.db-shm")), Data("shm".utf8))
    }

    func testCopyFileChunkedPreservesLargeFile() throws {
        let source = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: source) }
        let destinationParent = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: destinationParent) }
        let bytes = Data((0..<200_000).map { UInt8($0 % 251) })
        let file = source.appendingPathComponent("big.bin")
        try bytes.write(to: file)
        let result = W6FolderImport.copyFile(source: file, into: destinationParent)
        XCTAssertTrue(result.failed.isEmpty, "failures: \(result.failed)")
        XCTAssertEqual(result.copiedBytes, 200_000)
        XCTAssertEqual(try Data(contentsOf: destinationParent.appendingPathComponent("big.bin")), bytes)
    }

    func testUniqueNameNumbering() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertEqual(W6FolderImport.uniqueName(for: "Report.pdf", in: dir), "Report.pdf")
        try write("x", to: dir.appendingPathComponent("Report.pdf"))
        XCTAssertEqual(W6FolderImport.uniqueName(for: "Report.pdf", in: dir), "Report 2.pdf")
        try write("x", to: dir.appendingPathComponent("Report 2.pdf"))
        XCTAssertEqual(W6FolderImport.uniqueName(for: "Report.pdf", in: dir), "Report 3.pdf")
        XCTAssertEqual(W6FolderImport.uniqueName(for: "README", in: dir), "README")
    }

    // MARK: - Batch ZIP (feature 1)

    func testBatchArchivePacksSelectedFiles() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try write("aaa", to: dir.appendingPathComponent("a.txt"))
        let sub = dir.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: false)
        try write("bb", to: sub.appendingPathComponent("b.txt"))
        let entries = W6FileBrowser.list(root: dir)
        let output = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: output) }
        let zipURL = try W6BatchArchive.archive(entries: entries, to: output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: zipURL.path))
        let archive = try Archive(url: zipURL, accessMode: .read)
        let names = archive.map(\.path).sorted()
        XCTAssertEqual(names, ["a.txt", "sub/b.txt"])
    }

    func testBatchArchiveEmptySelectionThrows() throws {
        let output = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: output) }
        XCTAssertThrowsError(try W6BatchArchive.archive(entries: [], to: output))
    }

    // MARK: - Splash-ad path table (feature 3)

    func testSplashTableCoversSevenApps() {
        XCTAssertEqual(W6SplashAdPathTable.entries.count, 14)
        let bundleIDs = Set(W6SplashAdPathTable.entries.map(\.bundleID))
        XCTAssertEqual(bundleIDs.count, 8)
        // 7 apps: 携程旅行 ships under two bundle IDs.
        XCTAssertEqual(W6SplashAdPathTable.apps.count, 7)
        XCTAssertEqual(W6SplashAdPathTable.apps.map(\.appName),
                       ["淘宝", "京东", "大众点评", "中国移动", "腾讯视频", "番茄小说", "携程旅行"])
    }

    func testSplashTableEntriesAreAllPendingVerification() {
        XCTAssertTrue(W6SplashAdPathTable.entries.allSatisfy { $0.verification == .pendingVerification })
        XCTAssertEqual(W6SplashAdPathTable.entries(for: "com.taobao.taobao4iphone").count, 3)
        XCTAssertEqual(W6SplashAdPathTable.entries(for: "com.tencent.live4iphone").count, 5)
        XCTAssertEqual(W6SplashAdPathTable.entries(for: "com.360buy.jdmobile").map(\.relativePath),
                       ["Library/Caches/startADImage"])
        XCTAssertEqual(W6SplashAdPathTable.entries(for: "com.dragon.read").map(\.relativePath),
                       ["Documents/TTAdSplashSimpleCache"])
        XCTAssertTrue(W6SplashAdPathTable.entries(for: "com.apple.mobilesafari").isEmpty)
    }

    func testSplashTableJSONRoundTrip() throws {
        let data = try JSONEncoder().encode(W6SplashAdPathTable.entries)
        let decoded = try W6SplashAdPathTable.decodeUpdatedTable(from: data)
        XCTAssertEqual(decoded, W6SplashAdPathTable.entries)
        XCTAssertThrowsError(try W6SplashAdPathTable.decodeUpdatedTable(from: Data("not json".utf8)))
    }

    func testSplashMatchesAgainstRealContainer() throws {
        let container = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: container) }
        let adDir = container.appendingPathComponent("Library/Caches/startADImage", isDirectory: true)
        try FileManager.default.createDirectory(at: adDir, withIntermediateDirectories: true)
        try write("ad", to: adDir.appendingPathComponent("splash.png"))
        let matches = W6SplashAdPathTable.matches(in: container, bundleID: "com.360buy.jdmobile")
        XCTAssertEqual(matches.count, 1)
        XCTAssertTrue(matches[0].exists)
        XCTAssertEqual(matches[0].byteCount, 2)
        XCTAssertTrue(matches[0].containerReachable)
        XCTAssertEqual(matches[0].entry.verification, .pendingVerification)
        let missing = W6SplashAdPathTable.matches(in: container, bundleID: "com.dragon.read")
        XCTAssertEqual(missing.count, 1)
        XCTAssertFalse(missing[0].exists)
        XCTAssertEqual(missing[0].byteCount, 0)
    }

    func testSplashGenericHints() throws {
        let container = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: container) }
        let sdkDir = container.appendingPathComponent("Library/Caches/BUAdSDK", isDirectory: true)
        try FileManager.default.createDirectory(at: sdkDir, withIntermediateDirectories: true)
        try write("x", to: sdkDir.appendingPathComponent("a.bin"))
        let found = W6SplashAdPathTable.genericMatches(in: container)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].entry.relativePath, "Library/Caches/BUAdSDK")
        XCTAssertEqual(found[0].byteCount, 1)
    }

    // MARK: - Cross-app sentinel (features 4 + 5)

    func testSentinelGate() {
        XCTAssertEqual(W6CrossAppBrowser.sentinelState(osBuild: "24C5037i"), .supported)
        XCTAssertEqual(W6CrossAppBrowser.sentinelState(osBuild: "24C5049d"),
                       .blocked(build: "24C5049d"))
        XCTAssertEqual(W6CrossAppBrowser.sentinelState(osBuild: nil), .unknownBuild(build: ""))
        XCTAssertEqual(W6CrossAppBrowser.sentinelState(osBuild: "garbage"), .unknownBuild(build: "garbage"))
    }

    func testCrossAppListRefusesBlockedBuild() {
        let app = W6CrossAppTarget(
            id: "com.example.app", bundleID: "com.example.app",
            name: "Example", containerPath: "/tmp")
        let listing = W6CrossAppBrowser.list(app: app, osBuild: "24C5049d")
        XCTAssertTrue(listing.entries.isEmpty)
        XCTAssertFalse(listing.reachable)
        XCTAssertFalse(listing.note.isEmpty)
        let unknown = W6CrossAppBrowser.list(app: app, osBuild: nil)
        XCTAssertTrue(unknown.entries.isEmpty)
        XCTAssertFalse(unknown.reachable)
    }

    func testCrossAppListWithoutContainerIsUnreachable() {
        let app = W6CrossAppTarget(
            id: "com.example.app", bundleID: "com.example.app",
            name: "Example", containerPath: nil)
        let listing = W6CrossAppBrowser.list(app: app, osBuild: "24C5037i")
        XCTAssertTrue(listing.entries.isEmpty)
        XCTAssertFalse(listing.reachable)
    }

    func testCrossAppCacheStatsUnreachableWhenBlocked() {
        let app = W6CrossAppTarget(
            id: "com.example.app", bundleID: "com.example.app",
            name: "Example", containerPath: "/tmp")
        let stat = W6CrossAppCacheStats.measure(app: app, osBuild: "24C5049d")
        XCTAssertFalse(stat.reachable)
        XCTAssertEqual(stat.totalBytes, 0)
        XCTAssertEqual(stat.splashAdPathsChecked,
                       W6SplashAdPathTable.entries(for: "com.example.app").count)
        XCTAssertTrue(W6CrossAppCacheStats.measureAll(apps: [], osBuild: "24C5037i").isEmpty)
    }

    // MARK: - Registration

    func testRegistrationCoversFiveFeatures() {
        XCTAssertEqual(W6Registration.all.count, 5)
        let ids = W6Registration.all.map(\.id)
        XCTAssertEqual(Set(ids).count, 5)
        XCTAssertEqual(ids, [
            "w6-batch-selection", "w6-folder-import", "w6-splash-ad-paths",
            "w6-cross-app-browse", "w6-cross-app-cache",
        ])
        XCTAssertTrue(W6Registration.all.allSatisfy { !$0.title.isEmpty && !$0.detail.isEmpty })
        let splash = W6Registration.registration(for: "w6-splash-ad-paths")
        XCTAssertEqual(splash?.title, "开屏广告缓存路径识别")
        XCTAssertEqual(splash?.category, .deviceDiagnostics)
        XCTAssertEqual(splash?.viewKind, .splashAdPaths)
        XCTAssertEqual(W6Registration.registration(for: "w6-folder-import")?.viewKind, .fileBrowser)
        XCTAssertEqual(W6Registration.registration(for: "w6-batch-selection")?.viewKind, .fileBrowser)
        XCTAssertNil(W6Registration.registration(for: "w6-does-not-exist"))
    }

    func testFormatBytesIsNonEmpty() {
        XCTAssertFalse(W6Format.bytes(0).isEmpty)
        XCTAssertFalse(W6Format.bytes(1_500_000).isEmpty)
    }
}
