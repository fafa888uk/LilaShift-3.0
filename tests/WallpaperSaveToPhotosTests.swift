// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import XCTest
@testable import GestaltX

final class WallpaperSaveToPhotosTests: XCTestCase {
    let fm = FileManager.default
    /// A real 1x1 transparent PNG.
    let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8Xw8AAwMCAO+ip1sAAAAASUVORK5CYII=")!
    /// A larger file with a JPEG magic-byte signature.
    var jpeg: Data { Data([0xFF, 0xD8, 0xFF, 0xE0]) + Data(repeating: 0, count: 196) }

    func localStore(_ storage: URL) -> CustomizationStore {
        CustomizationStore(storage: storage, device: "test-device", resolver: { _ in
            fatalError("wallpaperImageData must not request system-container access")
        })
    }
    func makePack(_ pack: WallpaperPack, storage: URL, files: [String: Data] = [:]) throws {
        let directory = storage.appendingPathComponent("Wallpapers/\(pack.id.uuidString)")
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        for descriptor in pack.descriptors {
            let folder = directory.appendingPathComponent(descriptor.folder)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            for (name, data) in files { try data.write(to: folder.appendingPathComponent(name)) }
        }
        try CustomizationFiles.saveVerified(pack, to: directory.appendingPathComponent("Pack.plist"))
    }
    func tempStorage() throws -> URL {
        let storage = fm.temporaryDirectory.appendingPathComponent("GX-WallpaperSave-\(UUID().uuidString)")
        try fm.createDirectory(at: storage, withIntermediateDirectories: false)
        return storage
    }

    func testWallpaperImageDataReturnsPngBytes() async throws {
        let storage = try tempStorage()
        defer { try? fm.removeItem(at: storage) }
        let pack = WallpaperPack(id: UUID(), name: "Test", descriptors: [.init(folder: UUID().uuidString, provider: .collections)])
        try makePack(pack, storage: storage, files: ["Wallpaper.png": png])
        let data = try await localStore(storage).wallpaperImageData(pack.id)
        XCTAssertEqual(data, png)
    }

    func testWallpaperImageDataReturnsLargestImage() async throws {
        let storage = try tempStorage()
        defer { try? fm.removeItem(at: storage) }
        let pack = WallpaperPack(id: UUID(), name: "Test", descriptors: [.init(folder: UUID().uuidString, provider: .collections)])
        try makePack(pack, storage: storage, files: ["Wallpaper.png": png, "Photo.jpg": jpeg])
        let data = try await localStore(storage).wallpaperImageData(pack.id)
        XCTAssertEqual(data, jpeg)
    }

    func testWallpaperImageDataThrowsWithoutImages() async throws {
        let storage = try tempStorage()
        defer { try? fm.removeItem(at: storage) }
        let store = localStore(storage)
        let empty = WallpaperPack(id: UUID(), name: "Empty", descriptors: [])
        try makePack(empty, storage: storage)
        do {
            _ = try await store.wallpaperImageData(empty.id)
            XCTFail("Expected wallpaperImageData to throw for a pack with no descriptors")
        } catch let failure as CustomizationFailure {
            XCTAssertEqual(failure.key, "This pack contains no compatible wallpapers.")
        }
        let binOnly = WallpaperPack(id: UUID(), name: "Bin", descriptors: [.init(folder: UUID().uuidString, provider: .collections)])
        try makePack(binOnly, storage: storage, files: ["Asset.bin": Data("not an image".utf8)])
        do {
            _ = try await store.wallpaperImageData(binOnly.id)
            XCTFail("Expected wallpaperImageData to throw for a pack with no image files")
        } catch {}
    }
}
