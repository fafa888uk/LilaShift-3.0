import Foundation
import XCTest
@testable import GestaltX

/// Model cache probe tests (A20, Erosion-CN
/// `VoiceMemosAIView.probeAIModelCaches`): the file/size counter
/// over a temp directory tree — depth limit, symlink handling, and
/// the per-path probe. Only counting is tested; no device is needed.
final class ModelCacheProbeTests: XCTestCase {
    private func makeTree() throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("ModelCacheProbeTests_\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        // root/a.txt (3 bytes), root/sub/b.txt (5 bytes), root/sub/deep/c.txt (7 bytes)
        try "abc".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let sub = root.appendingPathComponent("sub", isDirectory: true)
        try fm.createDirectory(at: sub, withIntermediateDirectories: true)
        try "abcde".write(to: sub.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        let deep = sub.appendingPathComponent("deep", isDirectory: true)
        try fm.createDirectory(at: deep, withIntermediateDirectories: true)
        try "abcdefg".write(to: deep.appendingPathComponent("c.txt"), atomically: true, encoding: .utf8)
        return root
    }

    func testCountFilesAndSize() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let (count, bytes) = ModelCacheProbe.countFilesAndSize(at: root, maxDepth: 4)
        XCTAssertEqual(count, 3)
        XCTAssertEqual(bytes, 15)
    }

    func testDepthLimit() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        // Depth 0 counts only the root level.
        let (count, bytes) = ModelCacheProbe.countFilesAndSize(at: root, maxDepth: 0)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(bytes, 3)
        // Depth 1 reaches root/sub but not root/sub/deep.
        let (count1, _) = ModelCacheProbe.countFilesAndSize(at: root, maxDepth: 1)
        XCTAssertEqual(count1, 2)
    }

    func testSymlinksAreNotFollowed() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        // A symlink to the sub directory must not be descended into,
        // and a symlink to a file must not be counted as a file.
        let fm = FileManager.default
        try fm.createSymbolicLink(at: root.appendingPathComponent("linkdir"),
                                   withDestinationURL: root.appendingPathComponent("sub"))
        try fm.createSymbolicLink(at: root.appendingPathComponent("linkfile.txt"),
                                   withDestinationURL: root.appendingPathComponent("a.txt"))
        let (count, bytes) = ModelCacheProbe.countFilesAndSize(at: root, maxDepth: 4)
        XCTAssertEqual(count, 3)
        XCTAssertEqual(bytes, 15)
    }

    func testProbePathOverTempDirectory() throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let item = ModelCacheProbe.probePath(title: "Test", id: "test", path: root.path,
                                             notFoundNote: "missing", deniedNote: "denied")
        XCTAssertTrue(item.accessible)
        XCTAssertEqual(item.fileCount, 3)
        XCTAssertEqual(item.totalBytes, 15)
    }

    func testProbeSystemPathMissingReturnsNil() {
        XCTAssertNil(ModelCacheProbe.probeSystemPath(
            title: "Missing", id: "missing",
            path: "/tmp/definitely-not-a-real-path-\(UUID().uuidString)"))
    }

    func testFormatBytes() {
        XCTAssertEqual(ModelCacheProbe.formatBytes(512), "512 B")
        XCTAssertEqual(ModelCacheProbe.formatBytes(2048), "2.0 KB")
        XCTAssertEqual(ModelCacheProbe.formatBytes(3 * 1024 * 1024), "3.0 MB")
    }
}
