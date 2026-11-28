// SPDX-License-Identifier: GPL-3.0-only
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum W9WallpaperStudio {
    enum Layer: Equatable, Sendable { case background, foreground }
    enum Failure: Error, Equatable { case unreadable, tooLarge, unsupportedImage, renderFailed }

    static let sourceByteLimit = 20 * 1_024 * 1_024

    static func loadImage(at url: URL, for layer: Layer) throws -> CGImage {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try readBounded(url)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) == 1,
              let identifier = CGImageSourceGetType(source),
              let type = UTType(identifier as String),
              (layer == .foreground ? type == .png : [.png, .jpeg, .heic].contains(type)),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              (1...16_000).contains(width), (1...16_000).contains(height),
              width * height <= 64_000_000 else { throw Failure.unsupportedImage }

        let settings: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2_048,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, settings as CFDictionary) else {
            throw Failure.unsupportedImage
        }
        if layer == .foreground {
            switch image.alphaInfo {
            case .premultipliedFirst, .premultipliedLast, .first, .last: break
            default: throw Failure.unsupportedImage
            }
        }
        return image
    }

    private static func readBounded(_ url: URL) throws -> Data {
        do {
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            var buffer = Data()
            while buffer.count <= sourceByteLimit {
                let count = min(65_536, sourceByteLimit + 1 - buffer.count)
                guard let chunk = try file.read(upToCount: count), !chunk.isEmpty else { return buffer }
                buffer.append(chunk)
            }
            throw Failure.tooLarge
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.unreadable
        }
    }

    /// The background fills the canvas with a horizontal margin for movement.
    /// Foreground fits inside an 80% box and moves in the opposite direction.
    static func placement(
        background: CGSize, foreground: CGSize?, canvas: CGSize, shift: Double
    ) -> (background: CGRect, foreground: CGRect?) {
        let clamped = shift.isFinite ? max(-1, min(1, shift)) : 0
        let amount = CGFloat(clamped)
        let pad = canvas.width * 0.04
        let scale = max((canvas.width + pad * 2) / background.width, canvas.height / background.height)
        let backgroundRect = centered(background, scale: scale, canvas: canvas, dx: -pad * amount)
        let foregroundRect = foreground.map { size in
            let fit = min(canvas.width * 0.8 / size.width, canvas.height * 0.8 / size.height)
            return centered(size, scale: fit, canvas: canvas, dx: canvas.width * 0.09 * amount)
        }
        return (backgroundRect, foregroundRect)
    }

    private static func centered(_ size: CGSize, scale: CGFloat, canvas: CGSize, dx: CGFloat) -> CGRect {
        let w = size.width * scale
        let h = size.height * scale
        return CGRect(x: (canvas.width - w) / 2 + dx, y: (canvas.height - h) / 2, width: w, height: h)
    }

    static func render(
        background: CGImage, foreground: CGImage?, shift: Double, exporting: Bool
    ) throws -> CGImage {
        let width = exporting ? 1_080 : 270
        let height = exporting ? 1_920 : 480
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else { throw Failure.renderFailed }
        let canvas = CGSize(width: CGFloat(width), height: CGFloat(height))
        let images = placement(
            background: CGSize(width: CGFloat(background.width), height: CGFloat(background.height)),
            foreground: foreground.map { CGSize(width: CGFloat($0.width), height: CGFloat($0.height)) },
            canvas: canvas, shift: shift
        )
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(origin: .zero, size: canvas))
        context.interpolationQuality = .high
        context.draw(background, in: images.background)
        if let foreground, let rect = images.foreground { context.draw(foreground, in: rect) }
        guard let image = context.makeImage() else { throw Failure.renderFailed }
        return image
    }

    static func png(background: CGImage, foreground: CGImage?, shift: Double) throws -> Data {
        let image = try render(background: background, foreground: foreground, shift: shift, exporting: true)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
            throw Failure.renderFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure.renderFailed }
        return data as Data
    }
}
