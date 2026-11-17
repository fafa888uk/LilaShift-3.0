import Foundation
import UIKit
import XCTest
@testable import GestaltX

/// Dialer skin tests (A18, Erosion-CN `KeypadManager`): the region
/// code is detected from existing filenames, PNG validation rejects
/// non-images, apply writes all six artwork files with backups
/// and restore returns the exact originals, and a theme ZIP with a
/// path-traversal entry is refused. No device is needed: a temp
/// directory stands in for the Phone container.
final class DialerSkinTests: XCTestCase {
    private func pngData(color: UIColor = .red) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10), format: format)
        return renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }.pngData()!
    }

    private func makeContainer(seeded: [String: Data] = [:]) -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("DialerSkinTests_\(UUID().uuidString)", isDirectory: true)
        let dir = root.appendingPathComponent("Library/Caches/TelephonyUI-10", isDirectory: true)
        try! fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, data) in seeded {
            try! data.write(to: dir.appendingPathComponent(name), options: .atomic)
        }
        return root
    }

    private func telephonyDir(in container: URL) -> URL {
        container.appendingPathComponent("Library/Caches/TelephonyUI-10", isDirectory: true)
    }

    func testRegCodeDetection() {
        XCTAssertEqual(DialerSkin.regCode(from: ["other-1---mask.png"]), "other")
        XCTAssertEqual(DialerSkin.regCode(from: ["LL-1---mask.png", "other-2---mask.png"]), "LL")
        XCTAssertEqual(DialerSkin.regCode(from: []), "other")
        XCTAssertEqual(DialerSkin.regCode(from: ["README.txt"]), "other")
    }

    func testFileNames() {
        let names = DialerSkin.KeypadID.one.fileNames(withPrefix: "other")
        XCTAssertEqual(names.count, 6)
        XCTAssertEqual(names[0], "other-1---mask.png")
        XCTAssertEqual(names[1], "other-1---white.png")
        XCTAssertEqual(DialerSkin.KeypadID.one.accentedFileName(withPrefix: "other", dark: false), "other-1---mask.png")
        XCTAssertEqual(DialerSkin.KeypadID.one.accentedFileName(withPrefix: "other", dark: true), "other-1---white.png")
        XCTAssertEqual(DialerSkin.KeypadID.star.keyNumber, "*")
        XCTAssertEqual(DialerSkin.KeypadID.pound.keyNumber, "#")
    }

    func testPNGValidation() {
        XCTAssertTrue(DialerSkin.isValidPNGData(pngData()))
        XCTAssertFalse(DialerSkin.isValidPNGData(Data()))
        XCTAssertFalse(DialerSkin.isValidPNGData(Data("not a png".utf8)))
        XCTAssertFalse(DialerSkin.isValidPNGData(Data(repeating: 0, count: 100)))
        // PNG signature but truncated/garbage body is not a decodable image.
        var sig = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        sig.append(Data(repeating: 0, count: 100))
        XCTAssertFalse(DialerSkin.isValidPNGData(sig))
    }

    func testApplyAndRestoreRoundTrip() throws {
        let original = pngData(color: .blue)
        let replacement = pngData(color: .red)
        let container = makeContainer(seeded: ["other-1---mask.png": original])
        defer { try? FileManager.default.removeItem(at: container) }
        let result = try DialerSkin.apply(images: [.one: replacement], container: container)
        XCTAssertEqual(result.applied, 6)
        XCTAssertEqual(result.failed, 0)
        let dir = telephonyDir(in: container)
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("other-1---mask.png")), replacement)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("other-1---mask.png.bak").path))
        let current = try DialerSkin.currentKeypads(container: container, dark: false)
        XCTAssertEqual(current[.one], replacement)
        let restored = try DialerSkin.restore(container: container)
        XCTAssertEqual(restored, 6)
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("other-1---mask.png")), original)
    }

    func testRestoreDeletesOriginallyAbsentFiles() throws {
        let replacement = pngData(color: .red)
        let container = makeContainer()
        defer { try? FileManager.default.removeItem(at: container) }
        let result = try DialerSkin.apply(images: [.two: replacement], container: container)
        XCTAssertEqual(result.applied, 6)
        let dir = telephonyDir(in: container)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("other-2-A B C--mask.png").path))
        let restored = try DialerSkin.restore(container: container)
        XCTAssertEqual(restored, 6)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("other-2-A B C--mask.png").path))
    }

    func testInvalidImageIsSkipped() throws {
        let original = pngData(color: .blue)
        let container = makeContainer(seeded: ["other-1---mask.png": original])
        defer { try? FileManager.default.removeItem(at: container) }
        let result = try DialerSkin.apply(images: [.one: Data("garbage".utf8)], container: container)
        XCTAssertEqual(result.applied, 0)
        XCTAssertEqual(result.failed, 1)
        XCTAssertEqual(try Data(contentsOf: telephonyDir(in: container).appendingPathComponent("other-1---mask.png")), original)
    }

    func testResize() {
        let resized = DialerSkin.resize(pngData(), to: CGSize(width: 250, height: 250), circle: true)
        XCTAssertTrue(DialerSkin.isValidPNGData(resized))
        XCTAssertEqual(UIImage(data: resized)?.size, CGSize(width: 250, height: 250))
        let garbage = Data("nope".utf8)
        XCTAssertEqual(DialerSkin.resize(garbage, to: CGSize(width: 100, height: 100)), garbage)
    }

    // MARK: - Theme ZIP import

    private func crc32(_ data: Data) -> UInt32 {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
            table[i] = c
        }
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFFFFFF
    }

    /// A minimal ZIP with one stored (uncompressed) entry.
    private func storedZip(entryName: String, data: Data) -> Data {
        var out = Data()
        func u16(_ v: UInt16) { out.append(UInt8(v & 0xFF)); out.append(UInt8(v >> 8)) }
        func u32(_ v: UInt32) {
            out.append(UInt8(v & 0xFF)); out.append(UInt8((v >> 8) & 0xFF))
            out.append(UInt8((v >> 16) & 0xFF)); out.append(UInt8(v >> 24))
        }
        let nameData = Data(entryName.utf8)
        let crc = crc32(data)
        let localOffset = UInt32(out.count)
        out.append(contentsOf: [0x50, 0x4B, 0x03, 0x04])
        u16(20); u16(0); u16(0); u16(0); u16(0)
        u32(crc); u32(UInt32(data.count)); u32(UInt32(data.count))
        u16(UInt16(nameData.count)); u16(0)
        out.append(nameData)
        out.append(data)
        let cdOffset = UInt32(out.count)
        out.append(contentsOf: [0x50, 0x4B, 0x01, 0x02])
        u16(20); u16(20); u16(0); u16(0); u16(0); u16(0)
        u32(crc); u32(UInt32(data.count)); u32(UInt32(data.count))
        u16(UInt16(nameData.count)); u16(0); u16(0); u16(0); u16(0)
        u32(0); u32(localOffset)
        out.append(nameData)
        let cdSize = UInt32(out.count) - cdOffset
        out.append(contentsOf: [0x50, 0x4B, 0x05, 0x06])
        u16(0); u16(0); u16(1); u16(1)
        u32(cdSize); u32(cdOffset); u16(0)
        return out
    }

    func testThemeImportHappyPath() throws {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent("DialerTheme_\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: folder) }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let mask = pngData(color: .green)
        try mask.write(to: folder.appendingPathComponent("other-1---mask.png"), options: .atomic)
        try pngData(color: .yellow).write(to: folder.appendingPathComponent("other-1---white.png"), options: .atomic)
        let zipURL = fm.temporaryDirectory.appendingPathComponent("DialerTheme_\(UUID().uuidString).zip")
        defer { try? fm.removeItem(at: zipURL) }
        try fm.zipItem(at: folder, to: zipURL, shouldKeepParent: false)
        let matched = try DialerSkin.importTheme(from: zipURL, dark: false)
        XCTAssertEqual(matched[.one], mask)
    }

    func testThemeImportTraversalIsRefused() throws {
        let fm = FileManager.default
        let zipURL = fm.temporaryDirectory.appendingPathComponent("DialerEvil_\(UUID().uuidString).zip")
        defer { try? fm.removeItem(at: zipURL) }
        try storedZip(entryName: "../evil.txt", data: Data("evil".utf8))
            .write(to: zipURL, options: .atomic)
        XCTAssertThrowsError(try DialerSkin.importTheme(from: zipURL, dark: false)) { error in
            guard case DialerSkin.DialerSkinError.invalidTheme(let reason) = error else {
                return XCTFail("Expected invalidTheme, got \(error)")
            }
            XCTAssertTrue(reason.contains("illegal path"), "Traversal entry must be refused as an illegal path: \(reason)")
        }
    }

    func testThemeImportWithoutPNGsFails() throws {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent("DialerEmpty_\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: folder) }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try "hello".write(to: folder.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
        let zipURL = fm.temporaryDirectory.appendingPathComponent("DialerEmpty_\(UUID().uuidString).zip")
        defer { try? fm.removeItem(at: zipURL) }
        try fm.zipItem(at: folder, to: zipURL, shouldKeepParent: false)
        XCTAssertThrowsError(try DialerSkin.importTheme(from: zipURL, dark: false)) { error in
            XCTAssertTrue(error is DialerSkin.DialerSkinError)
        }
    }
}
