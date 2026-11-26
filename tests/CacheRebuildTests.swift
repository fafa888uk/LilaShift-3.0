import Foundation
import XCTest
@testable import GestaltX

/// Offline tests for the cache rebuild (A2, Erosion-CN's "清除並重建
/// 緩存", reimplemented for LilaShift's backup model): the current
/// device file is backed up first ("Before cache rebuild"), then the
/// live cache file is deleted so iOS regenerates it from the hardware
/// on restart. The manager's `rebuildCache()` clears the loaded
/// document and prompts a restart; it is device-only (it deletes the
/// real device file), so only the store is tested here. No device or
/// signing is needed: the store runs against a temporary directory.
final class CacheRebuildTests: XCTestCase {
    /// A store against a temporary directory, with a device document
    /// as the live file. Returns the store, the directory (removed by
    /// the caller) and the device URL.
    static func storeWithDevice() throws -> (GestaltFileStore, URL, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let deviceURL = directory.appendingPathComponent("com.apple.MobileGestalt.plist")
        let layout = MobileGestaltCacheLayout.originalProfile
        var cache = Data(count: layout.byteCount)
        cache[layout.greenTeaOffset] = 1
        cache[layout.notGreenTeaOffset] = 0
        cache[layout.validityOffset(for: layout.greenTeaIndex)] = 1
        cache[layout.validityOffset(for: layout.notGreenTeaIndex)] = 1
        let document = try GestaltDocument(data: PropertyListSerialization.data(fromPropertyList: [
            "CacheVersion": "24C5037i", "CacheUUID": layout.uuid,
            "CacheData": cache,
            "CacheExtra": [GestaltKeys.productType: "iPhone18,4", GestaltKeys.regionCode: "CH"],
        ], format: .binary, options: 0))
        try document.encoded().write(to: deviceURL)
        let store = GestaltFileStore(deviceURL: deviceURL,
                                     backupDirectory: directory.appendingPathComponent("backups"),
                                     deviceID: "rebuild-fixture", acquire: { 1 }, release: { _ in })
        return (store, directory, deviceURL)
    }

    func testRebuildBacksUpFirstThenDeletes() async throws {
        let (store, directory, deviceURL) = try Self.storeWithDevice()
        defer { try? FileManager.default.removeItem(at: directory) }
        let loaded = try await store.loadDevice()
        let liveBytes = try Data(contentsOf: deviceURL)
        let record = try await store.rebuildCache(expected: loaded)
        XCTAssert(record.reason == "Before cache rebuild",
                   "The rebuild archives the current device file first")
        XCTAssert(record.source == .device && record.deviceID == "rebuild-fixture",
                   "The pre-rebuild backup is a device backup of this device")
        XCTAssert(record.sha256 == GestaltFileStore.sha256Hex(of: liveBytes),
                   "The pre-rebuild backup digest matches the live bytes")
        XCTAssert(!FileManager.default.fileExists(atPath: deviceURL.path),
                   "The live cache file is deleted so iOS regenerates it on restart")
        let backups = try await store.backups()
        XCTAssert(backups.contains(where: { $0.reason == "Before cache rebuild" }),
                   "The pre-rebuild backup is listed and recoverable")
        let archived = try await store.backupData(record)
        XCTAssert(archived == liveBytes, "The archived backup holds the exact pre-rebuild bytes")
    }

    func testRebuildRejectsLocalDocument() async throws {
        let (store, directory, _) = try Self.storeWithDevice()
        defer { try? FileManager.default.removeItem(at: directory) }
        let loaded = try await store.loadDevice()
        let local = DocumentSnapshot(data: loaded.data, document: loaded.document,
                                     source: .local, name: "local")
        do {
            _ = try await store.rebuildCache(expected: local)
            XCTFail("Only a live device cache can be rebuilt")
        } catch is GestaltFailure { /* expected */ }
    }

    func testRebuildRejectsStaleDocument() async throws {
        let (store, directory, deviceURL) = try Self.storeWithDevice()
        defer { try? FileManager.default.removeItem(at: directory) }
        let loaded = try await store.loadDevice()
        // The file changed after it was loaded: the rebuild must refuse
        // rather than archive a state that no longer matches.
        var changed = Data(try Data(contentsOf: deviceURL))
        changed[0] = changed[0] ^ 0xFF
        try changed.write(to: deviceURL)
        do {
            _ = try await store.rebuildCache(expected: loaded)
            XCTFail("A rebuild must refuse when the live file changed since it was loaded")
        } catch is GestaltFailure { /* expected */ }
        XCTAssert(FileManager.default.fileExists(atPath: deviceURL.path),
                   "A refused rebuild leaves the live cache file in place")
    }
}
