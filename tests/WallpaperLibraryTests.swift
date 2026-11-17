// SPDX-License-Identifier: GPL-3.0-only
// Stage 8: personal wallpaper library — crop math, format
// conversion, store round-trips, Photos-export boundary, and the
// in-app home background setting. The Photos export is tested
// through a recording fake: no test ever claims a real Photos
// write.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import GestaltX

final class WallpaperLibraryTests: XCTestCase {
    private let fm = FileManager.default

    // MARK: - Image fixtures

    private func makePNG(width: Int, height: Int, red: CGFloat = 1, green: CGFloat = 0, blue: CGFloat = 0) -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let writer = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(writer, context.makeImage()!, nil)
        XCTAssert(CGImageDestinationFinalize(writer))
        return data as Data
    }

    private func makeJPEG(width: Int, height: Int) -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let writer = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(writer, context.makeImage()!, nil)
        XCTAssert(CGImageDestinationFinalize(writer))
        return data as Data
    }

    private func decodedSize(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (width, height)
    }

    private func tempStorage() throws -> URL {
        let storage = fm.temporaryDirectory.appendingPathComponent("GX-WallpaperLibrary-\(UUID().uuidString)")
        try fm.createDirectory(at: storage, withIntermediateDirectories: false)
        return storage
    }

    // MARK: - Crop math

    func testAspectFillCropWideSourceForTallTarget() {
        let crop = WallpaperCropSuggestions.aspectFillCrop(for: CGSize(width: 2000, height: 1000), targetAspectRatio: 9.0 / 19.5)
        XCTAssertEqual(crop.height, 1000, accuracy: 0.001)
        XCTAssertEqual(crop.width, 1000 * 9.0 / 19.5, accuracy: 0.001)
        XCTAssertEqual(crop.origin.x, (2000 - crop.width) / 2, accuracy: 0.001)
        XCTAssertEqual(crop.origin.y, 0, accuracy: 0.001)
    }

    func testAspectFillCropTallSourceForWideTarget() {
        let crop = WallpaperCropSuggestions.aspectFillCrop(for: CGSize(width: 1000, height: 2000), targetAspectRatio: 19.5 / 9.0)
        XCTAssertEqual(crop.width, 1000, accuracy: 0.001)
        XCTAssertEqual(crop.height, 1000 * 9.0 / 19.5, accuracy: 0.001)
        XCTAssertEqual(crop.origin.x, 0, accuracy: 0.001)
        XCTAssertEqual(crop.origin.y, (2000 - crop.height) / 2, accuracy: 0.001)
    }

    func testAspectFillCropSquareIsCentered() {
        let crop = WallpaperCropSuggestions.aspectFillCrop(for: CGSize(width: 1000, height: 2000), targetAspectRatio: 1)
        XCTAssertEqual(crop, CGRect(x: 0, y: 500, width: 1000, height: 1000))
    }

    func testAspectFillCropDegenerateInputReturnsZero() {
        XCTAssertEqual(WallpaperCropSuggestions.aspectFillCrop(for: .zero, targetAspectRatio: 9.0 / 19.5), .zero)
        XCTAssertEqual(WallpaperCropSuggestions.aspectFillCrop(for: CGSize(width: 100, height: 100), targetAspectRatio: 0), .zero)
        XCTAssertEqual(WallpaperCropSuggestions.aspectFillCrop(for: CGSize(width: -10, height: 100), targetAspectRatio: 1), .zero)
    }

    func testSuggestionsForDeviceHaveThreeOrientations() {
        let suggestions = WallpaperCropSuggestions.suggestions(
            for: CGSize(width: 1206, height: 2622),
            targetPixelSize: CGSize(width: 1320, height: 2868), deviceName: "iPhone 17 Pro Max")
        XCTAssertEqual(suggestions.count, 3)
        XCTAssertEqual(suggestions.map(\.orientation),
                       [.portrait, .landscape, .square])
        for suggestion in suggestions {
            XCTAssertTrue(suggestion.crop.width >= 1 && suggestion.crop.height >= 1)
            XCTAssertTrue(suggestion.crop.minX >= 0 && suggestion.crop.minY >= 0)
            XCTAssertTrue(suggestion.crop.maxX <= 1206.001 && suggestion.crop.maxY <= 2622.001)
            let cropAspect = suggestion.crop.width / suggestion.crop.height
            let targetAspect = CGFloat(suggestion.targetWidth) / CGFloat(suggestion.targetHeight)
            XCTAssertEqual(cropAspect, targetAspect, accuracy: 0.01)
        }
        // The source is smaller than the Pro Max screen: the
        // portrait suggestion honestly reports the upscale.
        XCTAssertTrue(suggestions[0].needsUpscale)
        XCTAssertEqual(suggestions[0].targetWidth, 1320)
        XCTAssertEqual(suggestions[0].targetHeight, 2868)
    }

    func testSuggestionsLargeSourceNeedsNoUpscale() {
        let suggestions = WallpaperCropSuggestions.suggestions(
            for: CGSize(width: 4000, height: 3000),
            targetPixelSize: CGSize(width: 1206, height: 2622), deviceName: "iPhone 17")
        XCTAssertFalse(suggestions[0].needsUpscale)
    }

    func testSuggestionsDegenerateInputReturnsEmpty() {
        XCTAssertTrue(WallpaperCropSuggestions.suggestions(
            for: .zero, targetPixelSize: CGSize(width: 1206, height: 2622), deviceName: "iPhone 17").isEmpty)
        XCTAssertTrue(WallpaperCropSuggestions.suggestions(
            for: CGSize(width: 100, height: 100), targetPixelSize: .zero, deviceName: "iPhone 17").isEmpty)
    }

    func testKnownDevicesHaveSaneSizes() {
        XCTAssertFalse(WallpaperDevice.knownDevices.isEmpty)
        for device in WallpaperDevice.knownDevices {
            XCTAssertGreaterThan(device.width, 0)
            XCTAssertGreaterThan(device.height, device.width, "\(device.name) must be portrait")
            let aspect = CGFloat(device.height) / CGFloat(device.width)
            XCTAssertGreaterThan(aspect, 1.5)
            XCTAssertLessThan(aspect, 2.5)
        }
        // Researched values (Apple tech specs, 2026-11): the Air is
        // 1260 × 2736, not the 1206 × 2622 of the 17 / 17 Pro.
        XCTAssertTrue(WallpaperDevice.knownDevices.contains(
            WallpaperDevice(name: "iPhone Air", width: 1260, height: 2736)))
        XCTAssertTrue(WallpaperDevice.knownDevices.contains(
            WallpaperDevice(name: "iPhone 17 Pro Max", width: 1320, height: 2868)))
        XCTAssertTrue(WallpaperDevice.knownDevices.contains(
            WallpaperDevice(name: "iPhone 17", width: 1206, height: 2622)))
    }

    // MARK: - Format conversion

    func testConvertPngToJpeg() {
        let png = makePNG(width: 64, height: 48)
        guard let jpeg = WallpaperImageConversion.convert(png, to: .jpeg) else {
            return XCTFail("PNG to JPEG conversion returned nil")
        }
        XCTAssertTrue(jpeg.starts(with: [0xFF, 0xD8, 0xFF] as [UInt8]))
        XCTAssertEqual(decodedSize(of: jpeg)?.width, 64)
        XCTAssertEqual(decodedSize(of: jpeg)?.height, 48)
    }

    func testConvertJpegToPng() {
        let jpeg = makeJPEG(width: 48, height: 64)
        guard let png = WallpaperImageConversion.convert(jpeg, to: .png) else {
            return XCTFail("JPEG to PNG conversion returned nil")
        }
        XCTAssertTrue(png.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] as [UInt8]))
        XCTAssertEqual(decodedSize(of: png)?.width, 48)
        XCTAssertEqual(decodedSize(of: png)?.height, 64)
    }

    func testConvertDownsamplesToMaxPixelSize() {
        let png = makePNG(width: 400, height: 300)
        guard let small = WallpaperImageConversion.convert(png, to: .png, maxPixelSize: 100) else {
            return XCTFail("Downsampled conversion returned nil")
        }
        let size = decodedSize(of: small)
        XCTAssertEqual(size?.width, 100)
        XCTAssertEqual(size?.height, 75)
    }

    func testConvertHeicOutputIsNotOffered() {
        let png = makePNG(width: 32, height: 32)
        XCTAssertNil(WallpaperImageConversion.convert(png, to: .heic))
        XCTAssertNil(WallpaperImageConversion.convert(png, to: .unsupported))
    }

    func testConvertInvalidDataReturnsNil() {
        XCTAssertNil(WallpaperImageConversion.convert(Data("not an image".utf8), to: .png))
        XCTAssertNil(WallpaperImageConversion.convert(Data(), to: .jpeg))
    }

    func testRenderCropProducesTargetSize() {
        let png = makePNG(width: 400, height: 800)
        let crop = WallpaperCropSuggestions.aspectFillCrop(
            for: CGSize(width: 400, height: 800), targetAspectRatio: 1206.0 / 2622.0)
        guard let rendered = WallpaperImageConversion.renderCrop(
            png, crop: crop, targetSize: CGSize(width: 1206, height: 2622), format: .png) else {
            return XCTFail("Crop render returned nil")
        }
        XCTAssertEqual(decodedSize(of: rendered)?.width, 1206)
        XCTAssertEqual(decodedSize(of: rendered)?.height, 2622)
    }

    func testRenderCropSquareTarget() {
        let png = makePNG(width: 800, height: 400)
        let crop = WallpaperCropSuggestions.aspectFillCrop(for: CGSize(width: 800, height: 400), targetAspectRatio: 1)
        guard let rendered = WallpaperImageConversion.renderCrop(
            png, crop: crop, targetSize: CGSize(width: 500, height: 500), format: .jpeg) else {
            return XCTFail("Square crop render returned nil")
        }
        XCTAssertEqual(decodedSize(of: rendered)?.width, 500)
        XCTAssertEqual(decodedSize(of: rendered)?.height, 500)
        XCTAssertTrue(rendered.starts(with: [0xFF, 0xD8, 0xFF] as [UInt8]))
    }

    func testRenderCropRejectsBadInput() {
        let png = makePNG(width: 64, height: 64)
        XCTAssertNil(WallpaperImageConversion.renderCrop(
            png, crop: .zero, targetSize: CGSize(width: 100, height: 100), format: .png))
        XCTAssertNil(WallpaperImageConversion.renderCrop(
            png, crop: CGRect(x: 0, y: 0, width: 64, height: 64),
            targetSize: CGSize(width: 100, height: 100), format: .heic))
        XCTAssertNil(WallpaperImageConversion.renderCrop(
            Data("junk".utf8), crop: CGRect(x: 0, y: 0, width: 10, height: 10),
            targetSize: CGSize(width: 100, height: 100), format: .png))
    }

    // MARK: - Store

    func testImportAndListRoundTrip() async throws {
        let storage = try tempStorage()
        defer { try? fm.removeItem(at: storage) }
        let store = WallpaperLibraryStore(storage: storage)
        let png = makePNG(width: 64, height: 48)
        let entry = try await store.importImage(png, name: "Sunset", category: .nature)
        XCTAssertEqual(entry.name, "Sunset")
        XCTAssertEqual(entry.category, .nature)
        XCTAssertFalse(entry.isFavorite)
        XCTAssertEqual(entry.format, .png)
        XCTAssertEqual(entry.width, 64)
        XCTAssertEqual(entry.height, 48)
        XCTAssertEqual(entry.byteCount, png.count)
        XCTAssertEqual(entry.sha256, CustomizationFiles.digest(png))
        let listed = try await store.list()
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed[0], entry)
        XCTAssertEqual(try await store.imageData(entry.id), png)
        let thumbnail = try await store.thumbnailData(entry.id)
        XCTAssertNotNil(thumbnail)
        XCTAssertTrue(thumbnail?.starts(with: [0x89, 0x50, 0x4E, 0x47] as [UInt8]) == true)
    }

    func testImportRejectsNonImage() async throws {
        let storage = try tempStorage()
        defer { try? fm.removeItem(at: storage) }
        let store = WallpaperLibraryStore(storage: storage)
        do {
            _ = try await store.importImage(Data("not an image".utf8), name: "Bad", category: .other)
            XCTFail("Importing non-image data must throw")
        } catch let failure as CustomizationFailure {
            XCTAssertEqual(failure.key, "This image could not be used. Choose another image.")
        }
        XCTAssertTrue(try await store.list().isEmpty)
    }

    func testImportEmptyNameDefaultsToWallpaper() async throws {
        let storage = try tempStorage()
        defer { try? fm.removeItem(at: storage) }
        let store = WallpaperLibraryStore(storage: storage)
        let entry = try await store.importImage(makePNG(width: 16, height: 16), name: "   ", category: .other)
        XCTAssertEqual(entry.name, "Wallpaper")
    }

    func testImportImageFileReadsStagedFile() async throws {
        let storage = try tempStorage()
        defer { try? fm.removeItem(at: storage) }
        let store = WallpaperLibraryStore(storage: storage)
        let file = fm.temporaryDirectory.appendingPathComponent("GX-Test-\(UUID().uuidString).png")
        defer { try? fm.removeItem(at: file) }
        try makePNG(width: 32, height: 32).write(to: file)
        let entry = try await store.importImageFile(file, name: nil, category: .minimal)
        XCTAssertEqual(entry.name, file.deletingPathExtension().lastPathComponent)
        XCTAssertEqual(entry.category, .minimal)
    }

    func testFavoriteSortsFirst() async throws {
        let storage = try tempStorage()
        defer { try? fm.removeItem(at: storage) }
        let store = WallpaperLibraryStore(storage: storage)
        let first = try await store.importImage(makePNG(width: 16, height: 16), name: "First", category: .other)
        let second = try await store.importImage(makePNG(width: 16, height: 16, red: 0, green: 1), name: "Second", category: .other)
        _ = try await store.setFavorite(second.id, isFavorite: true)
        let listed = try await store.list()
        XCTAssertEqual(listed.map(\.id), [second.id, first.id])
        _ = try await store.setCategory(first.id, category: .gradient)
        XCTAssertEqual(try await store.list().first(where: { $0.id == first.id })?.category, .gradient)
    }

    func testRenameValidation() async throws {
        let storage = try tempStorage()
        defer { try? fm.removeItem(at: storage) }
        let store = WallpaperLibraryStore(storage: storage)
        let entry = try await store.importImage(makePNG(width: 16, height: 16), name: "Old", category: .other)
        let renamed = try await store.rename(entry.id, name: "  New Name  ")
        XCTAssertEqual(renamed.name, "New Name")
        do {
            _ = try await store.rename(entry.id, name: "   ")
            XCTFail("Renaming to a blank name must throw")
        } catch let failure as CustomizationFailure {
            XCTAssertEqual(failure.key, "Give the wallpaper a name of 1–64 characters.")
        }
        do {
            _ = try await store.rename(entry.id, name: String(repeating: "A", count: 65))
            XCTFail("Renaming to a 65-character name must throw")
        } catch {}
    }

    func testDeleteRemovesOnlyItsFolder() async throws {
        let storage = try tempStorage()
        defer { try? fm.removeItem(at: storage) }
        let store = WallpaperLibraryStore(storage: storage)
        let kept = try await store.importImage(makePNG(width: 16, height: 16), name: "Kept", category: .other)
        let removed = try await store.importImage(makePNG(width: 16, height: 16, red: 0, green: 1), name: "Removed", category: .other)
        try await store.delete(removed.id)
        XCTAssertEqual(try await store.list().map(\.id), [kept.id])
        // Deleting again is a no-op, not an error.
        try await store.delete(removed.id)
        XCTAssertEqual(try await store.list().count, 1)
    }

    func testImageDataRefusesTamperedBytes() async throws {
        let storage = try tempStorage()
        defer { try? fm.removeItem(at: storage) }
        let store = WallpaperLibraryStore(storage: storage)
        let entry = try await store.importImage(makePNG(width: 16, height: 16), name: "Tamper", category: .other)
        let folder = storage.appendingPathComponent(entry.id.uuidString, isDirectory: true)
        try Data(repeating: 0, count: 64).write(to: folder.appendingPathComponent("Original.png"))
        do {
            _ = try await store.imageData(entry.id)
            XCTFail("Tampered bytes must be refused")
        } catch let failure as CustomizationFailure {
            XCTAssertEqual(failure.key, "This wallpaper is damaged. Delete it and import it again.")
        }
    }

    func testUnknownCategoryFallsBackToOther() throws {
        let dict: [String: Any] = [
            "id": UUID().uuidString, "name": "Mystery", "category": "bogus-category",
            "isFavorite": false, "format": "png", "width": 10, "height": 10,
            "byteCount": 100, "sha256": "abc", "createdAt": Date(),
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
        let entry = try PropertyListDecoder().decode(WallpaperLibraryEntry.self, from: data)
        XCTAssertEqual(entry.category, .other)
    }

    func testListSkipsCorruptFolders() async throws {
        let storage = try tempStorage()
        defer { try? fm.removeItem(at: storage) }
        let store = WallpaperLibraryStore(storage: storage)
        let good = try await store.importImage(makePNG(width: 16, height: 16), name: "Good", category: .other)
        let broken = storage.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: broken, withIntermediateDirectories: false)
        try Data("junk".utf8).write(to: broken.appendingPathComponent("Entry.plist"))
        XCTAssertEqual(try await store.list().map(\.id), [good.id])
    }

    // MARK: - Photos export boundary (recording fake)

    actor FakeWallpaperPhotoExporter: WallpaperPhotoExporting {
        var saved: [(data: Data, filename: String)] = []
        var error: (any Error)?

        func setError(_ error: (any Error)?) {
            self.error = error
        }

        func saveToPhotos(_ data: Data, filename: String) async throws {
            if let error { throw error }
            saved.append((data, filename))
        }
    }

    func testSaveToPhotosRequestsExportWithOriginalBytes() async throws {
        let storage = try tempStorage()
        defer { try? fm.removeItem(at: storage) }
        let store = WallpaperLibraryStore(storage: storage)
        let fake = FakeWallpaperPhotoExporter()
        let model = await WallpaperLibraryModel(store: store, exporter: fake)
        let png = makePNG(width: 32, height: 24)
        let entry = try await store.importImage(png, name: "Beach", category: .nature)
        await model.saveToPhotos(entry)
        let saved = await fake.saved
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved[0].data, png)
        XCTAssertEqual(saved[0].filename, "Beach-wallpaper.png")
        let message = await model.message
        XCTAssertTrue(message?.contains("Photos") == true)
    }

    func testSaveToPhotosSurfacesExporterError() async throws {
        let storage = try tempStorage()
        defer { try? fm.removeItem(at: storage) }
        let store = WallpaperLibraryStore(storage: storage)
        let fake = FakeWallpaperPhotoExporter()
        await fake.setError(CustomizationFailure("Allow LilaShift to add photos in Settings, then try again."))
        let model = await WallpaperLibraryModel(store: store, exporter: fake)
        let entry = try await store.importImage(makePNG(width: 16, height: 16), name: "Nope", category: .other)
        await model.saveToPhotos(entry)
        let saved = await fake.saved
        XCTAssertTrue(saved.isEmpty)
        let message = await model.message
        XCTAssertTrue(message?.contains("Allow LilaShift") == true)
    }

    func testConvertAndSaveCopyKeepsOriginal() async throws {
        let storage = try tempStorage()
        defer { try? fm.removeItem(at: storage) }
        let store = WallpaperLibraryStore(storage: storage)
        let fake = FakeWallpaperPhotoExporter()
        let model = await WallpaperLibraryModel(store: store, exporter: fake)
        let entry = try await store.importImage(makePNG(width: 64, height: 48), name: "Original", category: .abstract)
        await model.convertAndSaveCopy(entry, to: .jpeg)
        let listed = try await store.list()
        XCTAssertEqual(listed.count, 2)
        XCTAssertTrue(listed.contains(where: { $0.id == entry.id }))
        XCTAssertTrue(listed.contains(where: { $0.name == "Original (JPEG)" && $0.format == .jpeg }))
    }

    func testSaveCroppedCopyHasTargetSize() async throws {
        let storage = try tempStorage()
        defer { try? fm.removeItem(at: storage) }
        let store = WallpaperLibraryStore(storage: storage)
        let fake = FakeWallpaperPhotoExporter()
        let model = await WallpaperLibraryModel(store: store, exporter: fake)
        let entry = try await store.importImage(makePNG(width: 400, height: 800), name: "Tall", category: .other)
        let suggestions = WallpaperCropSuggestions.suggestions(
            for: entry.pixelSize, targetPixelSize: CGSize(width: 1206, height: 2622), deviceName: "iPhone 17")
        guard let portrait = suggestions.first(where: { $0.orientation == .portrait }) else {
            return XCTFail("No portrait suggestion")
        }
        await model.saveCroppedCopy(entry, suggestion: portrait, format: .png)
        let listed = try await store.list()
        XCTAssertEqual(listed.count, 2)
        guard let copy = listed.first(where: { $0.id != entry.id }) else {
            return XCTFail("Cropped copy missing")
        }
        XCTAssertEqual(copy.width, 1206)
        XCTAssertEqual(copy.height, 2622)
    }

    // MARK: - Home background setting (store-level round-trip)

    func testHomeWallpaperIDRoundTripsThroughSettingsStore() throws {
        let directory = fm.temporaryDirectory.appendingPathComponent("GX-HomeBG-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: directory) }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = PersonalizationSettingsStore(directory: directory, deviceID: "test-device")
        XCTAssertNil(store.load().settings.homeWallpaperID)
        let id = UUID()
        var settings = PersonalizationSettings.defaults
        settings.homeWallpaperID = id
        try store.save(settings)
        XCTAssertEqual(store.load().settings.homeWallpaperID, id)
        // An old file without the field decodes as nil (the default).
        var oldSettings = PersonalizationSettings.defaults
        oldSettings.homeWallpaperID = nil
        try store.save(oldSettings)
        XCTAssertNil(store.load().settings.homeWallpaperID)
    }
}
