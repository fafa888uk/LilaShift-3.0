// SPDX-License-Identifier: GPL-3.0-only
// CPUImageDiffing — a deterministic, CPU-only perceptual image diffing
// for snapshot tests.
//
// Problem: swift-snapshot-testing 1.19.7's perceptual comparison
// (`perceptuallyCompare` in Snapshotting/UIImage.swift) renders the
// CILabDeltaE image through Core Image and thresholds it with a custom
// Metal kernel (MPSImageThresholdBinary via ThresholdImageProcessorKernel)
// whenever Metal is available. On GitHub's virtualized Mac runners the
// Metal device is host-dependent, and the Metal path reports wildly
// different Delta-E values from the same pixels: the Tools/Unlock
// captures differ from their baselines by at most Delta-E 1.52 / 0.40
// (measured pixel-by-pixel in Python, well inside the 2.0 threshold),
// yet the harness reports max Delta-E 13.1 / 11.8 and fails the tests.
// The same code + baselines passed on #196/#208 and failed identically
// on #210/#220, with byte-identical captures between #210 and #220 —
// the comparison, not the rendering, flips between hosts.
//
// Fix: this file provides a `Diffing<UIImage>` that performs the
// perceptual comparison entirely on the CPU in pure Swift — sRGB to
// Lab conversion and CIE76 Delta-E, pixel by pixel — with no Core
// Image filter, no Metal kernel, and no GPU involved. The thresholds
// are unchanged (Delta-E 2.0, i.e. perceptualPrecision 0.98;
// precision 1.0, i.e. every pixel must pass). Only the computation
// path changes, from host-dependent Metal to deterministic CPU.
//
// The byte-equality fast path is kept: identical images pass without
// any Delta-E work. The PNG round-trip check from the library is
// also kept, so encoding noise cannot cause a false failure.

#if os(iOS) || os(tvOS)
import UIKit
import SnapshotTesting

extension Snapshotting where Value: SwiftUI.View, Format == UIImage {
    /// A snapshot strategy for SwiftUI views that renders exactly like
    /// the library's `.image` strategy but compares with the CPU-only
    /// perceptual diffing above instead of the library's Metal-based
    /// `perceptuallyCompare`. All parameters match the library's
    /// `.image` strategy; thresholds are unchanged (precision 1,
    /// perceptualPrecision 0.98).
    public static func cpuPerceptualImage(
        drawHierarchyInKeyWindow: Bool = false,
        precision: Float = 1,
        perceptualPrecision: Float = 0.98,
        layout: SwiftUISnapshotLayout = .sizeThatFits,
        traits: UITraitCollection = .init()
    ) -> Snapshotting {
        var strategy = Snapshotting.image(
            drawHierarchyInKeyWindow: drawHierarchyInKeyWindow,
            precision: precision,
            perceptualPrecision: perceptualPrecision,
            layout: layout,
            traits: traits
        )
        strategy.diffing = .cpuPerceptualImage(
            precision: precision,
            perceptualPrecision: perceptualPrecision,
            scale: traits.displayScale
        )
        return strategy
    }
}

extension Diffing where Value == UIImage {
    /// A perceptual image diffing strategy that computes Delta-E on the
    /// CPU in pure Swift, with no Metal or Core Image filter involved.
    ///
    /// - Parameters:
    ///   - precision: The percentage of pixels that must match (1.0
    ///     means every pixel must be within the Delta-E threshold).
    ///   - perceptualPrecision: The perceptual precision threshold,
    ///     expressed as a fraction (0.98 means Delta-E <= 2.0).
    ///   - scale: Scale to use when loading the reference image from
    ///     disk.
    public static func cpuPerceptualImage(
        precision: Float = 1, perceptualPrecision: Float = 0.98, scale: CGFloat? = nil
    ) -> Diffing {
        let imageScale: CGFloat
        if let scale = scale, scale != 0.0 {
            imageScale = scale
        } else {
            imageScale = UIScreen.main.scale
        }
        let toData: (UIImage) -> Data = { $0.pngData() ?? Data() }
        return .diff(
            toData: toData,
            fromData: { UIImage(data: $0, scale: imageScale)! }
        ) { old, new in
            guard
                let message = cpuCompare(
                    old, new, precision: precision, perceptualPrecision: perceptualPrecision)
            else { return nil }
            // Difference image for the failure attachment (blend-mode
            // difference, same technique the library uses).
            let difference = cpuDifferenceImage(old, new)
            let isEmptyImage = new.size == .zero
            let referenceAttachment = DiffAttachment.data(toData(old), name: "reference.png")
            let failureAttachment = DiffAttachment.data(
                toData(isEmptyImage ? old : new),
                name: "failure.png"
            )
            let differenceAttachment = DiffAttachment.data(toData(difference), name: "difference.png")
            return (
                message,
                [referenceAttachment, failureAttachment, differenceAttachment]
            )
        }
    }
}

/// Compare two images pixel by pixel on the CPU.
///
/// Both images are first converted to sRGB 8-bit RGBA via a CGContext
/// (the same conversion the library uses). If the bytes are identical,
/// the images match. Otherwise each pixel is converted from sRGB to
/// Lab and the CIE76 Delta-E is computed; a pixel fails when its
/// Delta-E exceeds `(1 - perceptualPrecision) * 100`. The test passes
/// when the fraction of passing pixels is at least `precision`.
private func cpuCompare(
    _ old: UIImage, _ new: UIImage, precision: Float, perceptualPrecision: Float
) -> String? {
    guard let oldCgImage = old.cgImage else {
        return "Reference image could not be loaded."
    }
    guard let newCgImage = new.cgImage else {
        return "Newly-taken snapshot could not be loaded."
    }
    guard newCgImage.width != 0, newCgImage.height != 0 else {
        return "Newly-taken snapshot is empty."
    }
    guard oldCgImage.width == newCgImage.width, oldCgImage.height == newCgImage.height else {
        return "Newly-taken snapshot@\(new.size) does not match reference@\(old.size)."
    }

    let width = oldCgImage.width
    let height = oldCgImage.height
    let pixelCount = width * height
    let bytesPerPixel = 4
    let byteCount = bytesPerPixel * pixelCount

    var oldBytes = [UInt8](repeating: 0, count: byteCount)
    guard let oldData = cpuContext(for: oldCgImage, data: &oldBytes)?.data else {
        return "Reference image's data could not be loaded."
    }
    // Fast path: identical bytes pass immediately.
    if let newContext = cpuContext(for: newCgImage), let newData = newContext.data {
        if memcmp(oldData, newData, byteCount) == 0 { return nil }
    }
    // PNG round-trip, as in the library: encoding noise alone must not fail.
    var newerBytes = [UInt8](repeating: 0, count: byteCount)
    guard
        let pngData = new.pngData(),
        let newerCgImage = UIImage(data: pngData)?.cgImage,
        let newerContext = cpuContext(for: newerCgImage, data: &newerBytes),
        let newerData = newerContext.data
    else {
        return "Newly-taken snapshot's data could not be loaded."
    }
    if memcmp(oldData, newerData, byteCount) == 0 { return nil }

    // Perceptual path: CIE76 Delta-E in Lab, computed in pure Swift.
    let deltaThreshold = (1 - perceptualPrecision) * 100
    var failingPixelCount = 0
    var maximumDeltaE: Float = 0
    let oldPtr = oldBytes
    let newPtr = newerBytes
    var index = 0
    while index < pixelCount {
        let byteOffset = index * bytesPerPixel
        let r1 = oldPtr[byteOffset]
        let g1 = oldPtr[byteOffset + 1]
        let b1 = oldPtr[byteOffset + 2]
        let r2 = newPtr[byteOffset]
        let g2 = newPtr[byteOffset + 1]
        let b2 = newPtr[byteOffset + 2]
        if r1 != r2 || g1 != g2 || b1 != b2 {
            let deltaE = cpuDeltaE(
                r1: r1, g1: g1, b1: b1, r2: r2, g2: g2, b2: b2)
            if deltaE > deltaThreshold {
                failingPixelCount += 1
                if deltaE > maximumDeltaE {
                    maximumDeltaE = deltaE
                }
            }
        }
        index += 1
    }

    let actualPixelPrecision = 1 - Float(failingPixelCount) / Float(pixelCount)
    guard actualPixelPrecision < precision else { return nil }
    let minimumPerceptualPrecision = 1 - min(maximumDeltaE / 100, 1)
    return """
      The percentage of pixels that match \(actualPixelPrecision) is less than required \(precision)
      The lowest perceptual color precision \(minimumPerceptualPrecision) is less than required \(perceptualPrecision)
      """
}

/// A CGContext that draws a CGImage into sRGB 8-bit RGBA bytes.
/// Identical to the conversion used by swift-snapshot-testing.
private func cpuContext(
    for cgImage: CGImage, data: UnsafeMutableRawPointer? = nil
) -> CGContext? {
    let bytesPerRow = cgImage.width * 4
    guard
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
            data: data,
            width: cgImage.width,
            height: cgImage.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else { return nil }
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
    return context
}

/// CIE76 Delta-E between two sRGB pixels.
///
/// Conversion: sRGB (gamma-encoded, D65) -> linear RGB -> XYZ (D65)
/// -> Lab (D65). All steps are the standard formulas; no GPU, no
/// Core Image, no host-dependent state.
private func cpuDeltaE(r1: UInt8, g1: UInt8, b1: UInt8, r2: UInt8, g2: UInt8, b2: UInt8) -> Float {
    let lab1 = cpuSRGBToLab(r: r1, g: g1, b: b1)
    let lab2 = cpuSRGBToLab(r: r2, g: g2, b: b2)
    let dL = lab1.0 - lab2.0
    let da = lab1.1 - lab2.1
    let db = lab1.2 - lab2.2
    return Float(sqrt(Double(dL * dL + da * da + db * db)))
}

private func cpuSRGBToLab(r: UInt8, g: UInt8, b: UInt8) -> (Float, Float, Float) {
    // sRGB gamma expansion to linear light.
    func linear(_ c: UInt8) -> Double {
        let v = Double(c) / 255.0
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }
    let rl = linear(r)
    let gl = linear(g)
    let bl = linear(b)
    // Linear sRGB (D65) -> XYZ (D65).
    let x = rl * 0.4124564 + gl * 0.3575761 + bl * 0.1804375
    let y = rl * 0.2126729 + gl * 0.7151522 + bl * 0.0721750
    let z = rl * 0.0193339 + gl * 0.1191920 + bl * 0.9503041
    // XYZ (D65) -> Lab (D65 white point: 0.95047, 1.0, 1.08883).
    func f(_ t: Double) -> Double {
        let delta = 6.0 / 29.0
        return t > delta * delta * delta ? pow(t, 1.0 / 3.0) : t / (3 * delta * delta) + 4.0 / 29.0
    }
    let fx = f(x / 0.95047)
    let fy = f(y / 1.0)
    let fz = f(z / 1.08883)
    let l = Float(116 * fy - 16)
    let a = Float(500 * (fx - fy))
    let b = Float(200 * (fy - fz))
    return (l, a, b)
}

/// Blend-mode difference image (new minus reference), for the failure
/// attachment. Same technique swift-snapshot-testing uses.
private func cpuDifferenceImage(_ old: UIImage, _ new: UIImage) -> UIImage {
    let width = max(old.size.width, new.size.width)
    let height = max(old.size.height, new.size.height)
    let scale = max(old.scale, new.scale)
    UIGraphicsBeginImageContextWithOptions(CGSize(width: width, height: height), true, scale)
    new.draw(at: .zero)
    old.draw(at: .zero, blendMode: .difference, alpha: 1)
    let differenceImage = UIGraphicsGetImageFromCurrentImageContext()!
    UIGraphicsEndImageContext()
    return differenceImage
}
#endif
