// SPDX-License-Identifier: GPL-3.0-only
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import GestaltX

final class W9WallpaperStudioTests: XCTestCase {
    func testNoUncoveredEdgeAtEitherExtreme() {
        let size = CGSize(width: 1080, height: 1920)
        for shift in [-1.0, 0, 1] {
            let plan = W9WallpaperStudio.placement(
                background: CGSize(width: 100, height: 300), foreground: nil, canvas: size, shift: shift
            )
            XCTAssertLessThanOrEqual(plan.background.minX, 1e-7)
            XCTAssertGreaterThanOrEqual(plan.background.maxX, size.width - 1e-7)
            XCTAssertLessThanOrEqual(plan.background.minY, 1e-7)
            XCTAssertGreaterThanOrEqual(plan.background.maxY, size.height - 1e-7)
        }
    }

    func testLayersMoveOppositelyAndClamp() throws {
        let size = CGSize(width: 1080, height: 1920)
        let source = CGSize(width: 1200, height: 1000)
        let center = W9WallpaperStudio.placement(background: source, foreground: source, canvas: size, shift: 0)
        let right = W9WallpaperStudio.placement(background: source, foreground: source, canvas: size, shift: 1)
        let clamped = W9WallpaperStudio.placement(background: source, foreground: source, canvas: size, shift: 3)
        XCTAssertLessThan(right.background.midX, center.background.midX)
        XCTAssertGreaterThan(try XCTUnwrap(right.foreground).midX, try XCTUnwrap(center.foreground).midX)
        XCTAssertEqual(right.background, clamped.background)
        XCTAssertEqual(right.foreground, clamped.foreground)
    }

    func testPNGOutputHasExpectedFormatAndSize() throws {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 12, height: 12, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 12, height: 12))
        let layer = try XCTUnwrap(context.makeImage())
        let data = try W9WallpaperStudio.png(background: layer, foreground: nil, shift: 0)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let identifier = try XCTUnwrap(CGImageSourceGetType(source))
        XCTAssertEqual(identifier as String, UTType.png.identifier)
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 1080)
        XCTAssertEqual(image.height, 1920)
    }

    func testUnrecognizedContentCannotBeLoadedAsAnImage() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not an image".utf8).write(to: url)
        XCTAssertThrowsError(try W9WallpaperStudio.loadImage(at: url, for: .foreground)) { error in
            XCTAssertEqual(error as? W9WallpaperStudio.Failure, .unsupportedImage)
        }
    }
}
