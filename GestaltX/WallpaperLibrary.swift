// SPDX-License-Identifier: GPL-3.0-only
// Wallpaper Library (Stage 8, TASKBOOK §7.1–§7.2): the user's own
// images — import, preview, resolution detection, crop, scale,
// format conversion, favorites, categories, delete, export to
// Photos — plus the device crop suggestions and the in-app home
// background setting.
//
// Honest boundary (TASKBOOK §7.3): iOS offers no public API for an
// app to set the system wallpaper or another app's launch image.
// This engine never claims otherwise: "apply" here means export
// the image to Photos (public Photos API) so the user sets it
// themselves, or use it as the in-app home background. The
// PosterBoard pack-apply path stays in CustomizationStore and is
// untouched by this file.
//
// The store only ever reads and writes inside its own storage root
// (AppDirectories.wallpaperLibraryStorage). It never touches the
// sandbox escape, another app's container, or any system directory.
import Foundation
import CoreGraphics
import ImageIO
import Photos
import UniformTypeIdentifiers

// MARK: - Categories

/// Wallpaper categories for the personal library. Fixed cases so a
/// stored category always decodes; an unknown raw value falls back
/// to `.other` instead of failing the whole entry.
enum WallpaperCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case nature
    case city
    case abstract
    case minimal
    case gradient
    case other

    var title: String {
        switch self {
        case .nature: return L("Nature")
        case .city: return L("City")
        case .abstract: return L("Abstract")
        case .minimal: return L("Minimal")
        case .gradient: return L("Gradient")
        case .other: return L("Other")
        }
    }

    init(decodingRawValue rawValue: String) {
        self = WallpaperCategory(rawValue: rawValue) ?? .other
    }
}

// MARK: - Entry

/// One image in the personal wallpaper library. The original bytes
/// live under the entry's folder in the library storage; this
/// record is the index (Entry.plist), verified by `sha256` over the
/// original bytes.
struct WallpaperLibraryEntry: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var category: WallpaperCategory
    var isFavorite: Bool
    var format: AppAppearanceImageFormat
    var width: Int
    var height: Int
    var byteCount: Int
    var sha256: String
    var createdAt: Date

    var pixelSize: CGSize { CGSize(width: width, height: height) }
    var aspectRatio: CGFloat { height > 0 ? CGFloat(width) / CGFloat(height) : 0 }
    var resolutionText: String { "\(width) × \(height)" }
}

/// The custom decoder lives in an extension on purpose: an
/// `init(from:)` written in the struct body would suppress the
/// memberwise initializer the store uses. Decoding an unknown
/// category raw value falls back to `.other` instead of failing
/// the whole entry.
extension WallpaperLibraryEntry {
    enum CodingKeys: String, CodingKey {
        case id, name, category, isFavorite, format, width, height, byteCount, sha256, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        let rawCategory = try container.decode(String.self, forKey: .category)
        category = WallpaperCategory(decodingRawValue: rawCategory)
        isFavorite = try container.decode(Bool.self, forKey: .isFavorite)
        format = try container.decode(AppAppearanceImageFormat.self, forKey: .format)
        width = try container.decode(Int.self, forKey: .width)
        height = try container.decode(Int.self, forKey: .height)
        byteCount = try container.decode(Int.self, forKey: .byteCount)
        sha256 = try container.decode(String.self, forKey: .sha256)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
}

// MARK: - Device crop suggestions (pure)

/// One crop suggestion: the centered aspect-fill crop of the source
/// image for a target size, plus whether rendering at the target
/// needs upscaling (the source is smaller than the target, so the
/// result will look soft — the UI says so instead of hiding it).
struct WallpaperCropSuggestion: Equatable, Sendable {
    enum Orientation: String, Equatable, Hashable, Sendable {
        case portrait
        case landscape
        case square
    }

    var orientation: Orientation
    var label: String
    var targetWidth: Int
    var targetHeight: Int
    var crop: CGRect
    var needsUpscale: Bool
}

/// A device screen in pixels. The sizes are the published display
/// pixel sizes (Apple tech specs, cross-checked against
/// useyourloaf.com/blog/iphone-17-screen-sizes and
/// ls.graphics/ideas/iphone-screen-sizes-and-resolutions, 2026-11):
/// iPhone Air 1260 × 2736, iPhone 17 / 17 Pro 1206 × 2622,
/// iPhone 17 Pro Max 1320 × 2868, iPhone 16 Pro Max 1320 × 2868,
/// iPhone 16 Pro 1206 × 2622, iPhone 16 Plus 1290 × 2796,
/// iPhone 16 / 15 Pro / 14 Pro 1179 × 2556, iPhone 15 Pro Max /
/// 15 Plus / 14 Pro Max 1290 × 2796, iPhone 14 Plus / 13 Pro Max
/// 1284 × 2778, iPhone 14 / 13 Pro / 13 1170 × 2532.
/// The live device is never taken from this table: the UI passes
/// the actual screen size (UIScreen bounds × scale) for "This
/// Device", so a device this table does not know still gets a
/// correct suggestion.
struct WallpaperDevice: Equatable, Hashable, Sendable {
    var name: String
    var width: Int
    var height: Int

    var pixelSize: CGSize { CGSize(width: width, height: height) }

    static let knownDevices: [WallpaperDevice] = [
        WallpaperDevice(name: "iPhone Air", width: 1260, height: 2736),
        WallpaperDevice(name: "iPhone 17", width: 1206, height: 2622),
        WallpaperDevice(name: "iPhone 17 Pro", width: 1206, height: 2622),
        WallpaperDevice(name: "iPhone 17 Pro Max", width: 1320, height: 2868),
        WallpaperDevice(name: "iPhone 16 Pro Max", width: 1320, height: 2868),
        WallpaperDevice(name: "iPhone 16 Pro", width: 1206, height: 2622),
        WallpaperDevice(name: "iPhone 16 Plus", width: 1290, height: 2796),
        WallpaperDevice(name: "iPhone 16", width: 1179, height: 2556),
        WallpaperDevice(name: "iPhone 15 Pro Max", width: 1290, height: 2796),
        WallpaperDevice(name: "iPhone 15 Pro", width: 1179, height: 2556),
        WallpaperDevice(name: "iPhone 15 Plus", width: 1290, height: 2796),
        WallpaperDevice(name: "iPhone 15", width: 1179, height: 2556),
        WallpaperDevice(name: "iPhone 14 Pro Max", width: 1290, height: 2796),
        WallpaperDevice(name: "iPhone 14 Pro", width: 1179, height: 2556),
        WallpaperDevice(name: "iPhone 14 Plus", width: 1284, height: 2778),
        WallpaperDevice(name: "iPhone 14", width: 1170, height: 2532),
        WallpaperDevice(name: "iPhone 13 Pro Max", width: 1284, height: 2778),
        WallpaperDevice(name: "iPhone 13 Pro", width: 1170, height: 2532),
        WallpaperDevice(name: "iPhone 13", width: 1170, height: 2532),
    ]
}

enum WallpaperCropSuggestions {
    /// The centered aspect-fill crop of `sourceSize` for a target
    /// aspect ratio (width / height). Returns `.zero` for a
    /// degenerate input instead of dividing by zero or guessing.
    static func aspectFillCrop(for sourceSize: CGSize, targetAspectRatio: CGFloat) -> CGRect {
        guard sourceSize.width > 0, sourceSize.height > 0, targetAspectRatio > 0 else { return .zero }
        let sourceAspect = sourceSize.width / sourceSize.height
        if sourceAspect > targetAspectRatio {
            let cropWidth = sourceSize.height * targetAspectRatio
            return CGRect(x: (sourceSize.width - cropWidth) / 2, y: 0, width: cropWidth, height: sourceSize.height)
        }
        let cropHeight = sourceSize.width / targetAspectRatio
        return CGRect(x: 0, y: (sourceSize.height - cropHeight) / 2, width: sourceSize.width, height: cropHeight)
    }

    /// Portrait, landscape and square suggestions for one target
    /// pixel size. The crop is always inside the source; when the
    /// source is smaller than the target, `needsUpscale` is true.
    static func suggestions(for sourceSize: CGSize, targetPixelSize: CGSize, deviceName: String) -> [WallpaperCropSuggestion] {
        guard sourceSize.width > 0, sourceSize.height > 0,
              targetPixelSize.width > 0, targetPixelSize.height > 0 else { return [] }
        let targets: [(WallpaperCropSuggestion.Orientation, String, Int, Int)] = [
            (.portrait, "\(deviceName) · \(L("Portrait"))", Int(targetPixelSize.width), Int(targetPixelSize.height)),
            (.landscape, "\(deviceName) · \(L("Landscape"))", Int(targetPixelSize.height), Int(targetPixelSize.width)),
            (.square, "\(deviceName) · \(L("Square"))",
             Int(min(targetPixelSize.width, targetPixelSize.height)),
             Int(min(targetPixelSize.width, targetPixelSize.height))),
        ]
        return targets.map { orientation, label, targetWidth, targetHeight in
            let crop = aspectFillCrop(for: sourceSize, targetAspectRatio: CGFloat(targetWidth) / CGFloat(targetHeight))
            return WallpaperCropSuggestion(
                orientation: orientation, label: label,
                targetWidth: targetWidth, targetHeight: targetHeight, crop: crop,
                needsUpscale: crop.width < CGFloat(targetWidth) || crop.height < CGFloat(targetHeight))
        }
    }
}

// MARK: - Format conversion (pure)

/// Image format conversion. PNG and JPEG outputs are produced with
/// ImageIO; HEIC input is decoded and re-encoded as PNG or JPEG —
/// HEIC output is not offered (the encode path is not verified on
/// this target, so it is left out instead of faked). The source is
/// downsampled during decode when `maxPixelSize` is set, so a
/// conversion never holds a full-size decoded image for the crop.
enum WallpaperImageConversion {
    static func convert(_ data: Data, to format: AppAppearanceImageFormat, maxPixelSize: Int? = nil) -> Data? {
        guard format == .png || format == .jpeg else { return nil }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        if let maxPixelSize { options[kCGImageSourceThumbnailMaxPixelSize] = max(1, maxPixelSize) }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        let type: CFString = format == .png ? UTType.png.identifier as CFString : UTType.jpeg.identifier as CFString
        guard let destination = CGImageDestinationCreateWithData(output, type, 1, nil) else { return nil }
        if format == .jpeg {
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        } else {
            CGImageDestinationAddImage(destination, image, nil)
        }
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// Renders the aspect-fill `crop` of `data` at exactly
    /// `targetSize` pixels, encoded as PNG or JPEG. The source is
    /// downsampled during decode to the target's longest side, so
    /// the render never holds a full-size decoded image. The crop
    /// rect is in source pixels; when the source is smaller than
    /// the target the result is upscaled (the caller shows the
    /// `needsUpscale` warning instead of hiding it). Returns nil
    /// when the source cannot be decoded or the crop is empty.
    static func renderCrop(_ data: Data, crop: CGRect, targetSize: CGSize, format: AppAppearanceImageFormat) -> Data? {
        guard format == .png || format == .jpeg,
              crop.width >= 1, crop.height >= 1,
              targetSize.width >= 1, targetSize.height >= 1,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let sourceWidth = properties[kCGImagePropertyPixelWidth] as? Int,
              let sourceHeight = properties[kCGImagePropertyPixelHeight] as? Int,
              sourceWidth > 0, sourceHeight > 0 else { return nil }
        let maxSide = Int(max(targetSize.width, targetSize.height))
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxSide),
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary) else { return nil }
        let scaleX = CGFloat(thumbnail.width) / CGFloat(sourceWidth)
        let scaleY = CGFloat(thumbnail.height) / CGFloat(sourceHeight)
        let thumbCrop = CGRect(
            x: crop.origin.x * scaleX, y: crop.origin.y * scaleY,
            width: crop.width * scaleX, height: crop.height * scaleY)
            .intersection(CGRect(x: 0, y: 0, width: thumbnail.width, height: thumbnail.height))
        guard thumbCrop.width >= 1, thumbCrop.height >= 1,
              let cropped = thumbnail.cropping(to: thumbCrop.integral) else { return nil }
        let targetWidth = Int(targetSize.width), targetHeight = Int(targetSize.height)
        guard let context = CGContext(
            data: nil, width: targetWidth, height: targetHeight,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        guard let rendered = context.makeImage() else { return nil }
        let output = NSMutableData()
        let type: CFString = format == .png ? UTType.png.identifier as CFString : UTType.jpeg.identifier as CFString
        guard let destination = CGImageDestinationCreateWithData(output, type, 1, nil) else { return nil }
        if format == .jpeg {
            CGImageDestinationAddImage(destination, rendered, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        } else {
            CGImageDestinationAddImage(destination, rendered, nil)
        }
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

// MARK: - Photos export boundary

/// The Photos write, behind a protocol so unit tests can record the
/// request instead of claiming a real Photos write. The live
/// implementation uses the public Photos API (add-only
/// authorization); it saves the image to Photos — it never sets the
/// system wallpaper, because no public API does that.
protocol WallpaperPhotoExporting: Sendable {
    func saveToPhotos(_ data: Data, filename: String) async throws
}

struct PhotoLibraryWallpaperExporter: WallpaperPhotoExporting {
    func saveToPhotos(_ data: Data, filename: String) async throws {
        var authorization = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if authorization == .notDetermined {
            authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        guard authorization == .authorized || authorization == .limited else {
            throw CustomizationFailure("Allow LilaShift to add photos in Settings, then try again.")
        }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = filename
            request.addResource(with: .photo, data: data, options: options)
        }
    }
}

// MARK: - Store

/// The personal wallpaper library. An actor so the file work is
/// serialized; every path stays under `storage`
/// (AppDirectories.wallpaperLibraryStorage). Validation reuses
/// `AppAppearanceValidatedImage` (5 MB, 4096 px, PNG/JPEG/HEIC by
/// magic bytes) — there is no second image validator.
actor WallpaperLibraryStore {
    private let storage: URL
    private let fm = FileManager.default

    init(storage: URL) {
        self.storage = storage
    }

    private func folder(_ id: UUID) -> URL {
        storage.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func entryURL(_ id: UUID) -> URL {
        folder(id).appendingPathComponent("Entry.plist")
    }

    private func loadEntry(_ id: UUID) throws -> WallpaperLibraryEntry {
        let data = try CustomizationFiles.read(CustomizationFiles.checked("Entry.plist", in: folder(id)))
        return try PropertyListDecoder().decode(WallpaperLibraryEntry.self, from: data)
    }

    private func saveEntry(_ entry: WallpaperLibraryEntry) throws {
        try CustomizationFiles.saveVerified(entry, to: entryURL(entry.id))
    }

    /// All entries, favorites first, then newest first. A folder
    /// whose Entry.plist cannot be read is skipped (it is not shown
    /// as a valid wallpaper); the folder itself is left alone.
    func list() throws -> [WallpaperLibraryEntry] {
        try fm.createDirectory(at: storage, withIntermediateDirectories: true)
        let folders = try fm.contentsOfDirectory(at: storage, includingPropertiesForKeys: [.isDirectoryKey])
        var entries: [WallpaperLibraryEntry] = []
        for url in folders {
            guard let id = UUID(uuidString: url.lastPathComponent),
                  (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                  let entry = try? loadEntry(id) else { continue }
            entries.append(entry)
        }
        return entries.sorted {
            if $0.isFavorite != $1.isFavorite { return $0.isFavorite }
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Imports validated image bytes as a new entry. The original
    /// bytes are stored verbatim; a 512 px PNG thumbnail is stored
    /// alongside for the list. The write is verified by reading the
    /// stored bytes back and comparing the SHA-256.
    func importImage(_ data: Data, name: String, category: WallpaperCategory) throws -> WallpaperLibraryEntry {
        guard case .success(let validated) = AppAppearanceValidatedImage.validate(data) else {
            throw CustomizationFailure("This image could not be used. Choose another image.")
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = WallpaperLibraryEntry(
            id: UUID(), name: trimmed.isEmpty ? L("Wallpaper") : trimmed, category: category,
            isFavorite: false, format: validated.format, width: validated.width, height: validated.height,
            byteCount: validated.byteCount, sha256: CustomizationFiles.digest(validated.data), createdAt: Date())
        let directory = folder(entry.id)
        try fm.createDirectory(at: storage, withIntermediateDirectories: true)
        guard !fm.fileExists(atPath: directory.path) else {
            throw CustomizationFailure("This wallpaper already exists. Import it again to make a copy.")
        }
        try fm.createDirectory(at: directory, withIntermediateDirectories: false)
        var saved = false
        defer { if !saved { try? fm.removeItem(at: directory) } }
        let fileExtension: String
        switch validated.format {
        case .png: fileExtension = "png"
        case .jpeg: fileExtension = "jpg"
        case .heic: fileExtension = "heic"
        case .unsupported: throw CustomizationFailure("This image format is not supported. Use PNG, JPEG, or HEIC.")
        }
        try validated.data.write(to: directory.appendingPathComponent("Original.\(fileExtension)"), options: .atomic)
        if let thumbnail = AppAppearanceValidatedImage.croppedThumbnailPNG(
            from: validated.data, crop: AppAppearanceCrop(), maxPixelSize: 512) {
            try thumbnail.write(to: directory.appendingPathComponent("Thumbnail.png"), options: .atomic)
        }
        try saveEntry(entry)
        let stored = try CustomizationFiles.read(
            CustomizationFiles.checked("Original.\(fileExtension)", in: directory))
        guard CustomizationFiles.digest(stored) == entry.sha256 else {
            throw CustomizationFailure("The wallpaper could not be saved and verified. Try again.")
        }
        saved = true
        return entry
    }

    /// Imports a staged file (from the document picker). The file is
    /// read through `CustomizationFiles.read`, so symlinks and
    /// oversized files are refused the same way as everywhere else.
    func importImageFile(_ url: URL, name: String?, category: WallpaperCategory) throws -> WallpaperLibraryEntry {
        let data = try CustomizationFiles.read(url)
        return try importImage(data, name: name ?? url.deletingPathExtension().lastPathComponent, category: category)
    }

    /// The stored original bytes, verified against the entry digest.
    func imageData(_ id: UUID) throws -> Data {
        let entry = try loadEntry(id)
        let fileExtension: String
        switch entry.format {
        case .png: fileExtension = "png"
        case .jpeg: fileExtension = "jpg"
        case .heic: fileExtension = "heic"
        case .unsupported: throw CustomizationFailure("This image format is not supported. Use PNG, JPEG, or HEIC.")
        }
        let data = try CustomizationFiles.read(CustomizationFiles.checked("Original.\(fileExtension)", in: folder(id)))
        guard CustomizationFiles.digest(data) == entry.sha256 else {
            throw CustomizationFailure("This wallpaper is damaged. Delete it and import it again.")
        }
        return data
    }

    /// The stored 512 px thumbnail, or nil when the entry was saved
    /// without one (older imports). The list shows a placeholder
    /// instead of failing.
    func thumbnailData(_ id: UUID) throws -> Data? {
        let url = folder(id).appendingPathComponent("Thumbnail.png")
        guard fm.fileExists(atPath: url.path) else { return nil }
        return try CustomizationFiles.read(CustomizationFiles.checked("Thumbnail.png", in: folder(id)))
    }

    func setFavorite(_ id: UUID, isFavorite: Bool) throws -> WallpaperLibraryEntry {
        var entry = try loadEntry(id)
        entry.isFavorite = isFavorite
        try saveEntry(entry)
        return entry
    }

    func setCategory(_ id: UUID, category: WallpaperCategory) throws -> WallpaperLibraryEntry {
        var entry = try loadEntry(id)
        entry.category = category
        try saveEntry(entry)
        return entry
    }

    func rename(_ id: UUID, name: String) throws -> WallpaperLibraryEntry {
        var entry = try loadEntry(id)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 64 else {
            throw CustomizationFailure("Give the wallpaper a name of 1–64 characters.")
        }
        entry.name = trimmed
        try saveEntry(entry)
        return entry
    }

    /// Deletes only this entry's own folder. Nothing outside the
    /// library storage is ever touched.
    func delete(_ id: UUID) throws {
        let directory = try CustomizationFiles.checked(id.uuidString, in: storage, missing: true)
        guard fm.fileExists(atPath: directory.path) else { return }
        _ = try loadEntry(id)
        try fm.removeItem(at: directory)
    }
}
