// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Native-write capability of the App Appearance backend.
///
/// The default is `.unknown`: no write capability is claimed until a real
/// probe verifies it. It must never be `.verifiedWritable` without a
/// verified write path, and a preview must never present itself as a
/// successful native edit.
enum AppAppearanceCapability: String, Equatable, Sendable {
    case unknown
    case readOnly
    case previewOnly
    case verifiedWritable
    case unsupported
    case failed

    /// The only safe starting state. A capability is never assumed.
    static var defaultCapability: AppAppearanceCapability { .unknown }
}

/// Image formats the appearance preview accepts. Detection is by magic
/// bytes only, so it never depends on a decoder succeeding, and it never
/// trusts a file extension.
enum AppAppearanceImageFormat: String, Equatable, Sendable {
    case png
    case jpeg
    case heic
    case unsupported

    var displayName: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        case .heic: return "HEIC"
        case .unsupported: return "—"
        }
    }

    static func detect(from data: Data) -> AppAppearanceImageFormat {
        guard !data.isEmpty else { return .unsupported }
        if data.count >= 8, data.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return .png }
        if data.count >= 3, data.prefix(3) == Data([0xFF, 0xD8, 0xFF]) { return .jpeg }
        if data.count >= 12, data[4..<8] == Data("ftyp".utf8) {
            // HEIC family brands, including the generic HEIF brands iOS
            // Photos may emit. A brand match only says the container is
            // HEIF; decodability is checked separately by validation.
            let brand = String(data: data[8..<12], encoding: .ascii) ?? ""
            if ["heic", "heix", "hevc", "hevx", "heim", "heis", "hevm", "hevs", "mif1", "msf1"].contains(brand) { return .heic }
        }
        return .unsupported
    }
}

/// A validated appearance image: a supported format whose pixels could be
/// read. The original bytes are kept so the preview can render a
/// downsampled thumbnail without ever decoding the full image twice.
struct AppAppearanceValidatedImage: Equatable, Sendable {
    let format: AppAppearanceImageFormat
    let width: Int
    let height: Int
    let byteCount: Int
    let data: Data

    /// Matches the existing preview import cap (5 MB).
    static let maximumBytes = 5 * 1024 * 1024
    /// Matches the LaunchArtworkImages dimension cap (4096 px).
    static let maximumDimension = 4096

    enum ValidationError: Swift.Error, Equatable {
        case empty
        case tooLarge
        case unsupportedFormat
        case undecodable
        case dimensionsTooLarge
    }

    static func validate(_ data: Data) -> Result<AppAppearanceValidatedImage, ValidationError> {
        guard !data.isEmpty else { return .failure(.empty) }
        guard data.count <= maximumBytes else { return .failure(.tooLarge) }
        let format = AppAppearanceImageFormat.detect(from: data)
        guard format != .unsupported else { return .failure(.unsupportedFormat) }
        guard let size = pixelSize(of: data) else { return .failure(.undecodable) }
        guard size.width <= maximumDimension, size.height <= maximumDimension else { return .failure(.dimensionsTooLarge) }
        return .success(AppAppearanceValidatedImage(format: format, width: size.width, height: size.height, byteCount: data.count, data: data))
    }

    private static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return nil }
        return (width, height)
    }

    /// Renders the cropped preview as PNG bytes, downsampled so the longest
    /// side is at most `maxPixelSize`. The source is never fully decoded:
    /// ImageIO downsamples during decode, then the crop is applied to the
    /// small image. Returns nil when the source cannot be decoded.
    static func croppedThumbnailPNG(from data: Data, crop: AppAppearanceCrop, maxPixelSize: Int = 512) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0,
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        // Map the crop rect from original pixels to thumbnail pixels.
        // The thumbnail preserves the aspect ratio, so the scale is uniform
        // up to rounding; separate scales handle the rounding either way.
        let cropRect = crop.rect(for: CGSize(width: width, height: height))
        let scaleX = CGFloat(thumbnail.width) / CGFloat(width)
        let scaleY = CGFloat(thumbnail.height) / CGFloat(height)
        let thumbCrop = CGRect(x: cropRect.origin.x * scaleX, y: cropRect.origin.y * scaleY,
                               width: cropRect.width * scaleX, height: cropRect.height * scaleY)
            .intersection(CGRect(x: 0, y: 0, width: thumbnail.width, height: thumbnail.height))
        guard thumbCrop.width >= 1, thumbCrop.height >= 1 else { return nil }
        let cropped = thumbnail.cropping(to: thumbCrop.integral) ?? thumbnail
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cropped, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

extension AppAppearanceValidatedImage.ValidationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .empty: return L("This image is empty.")
        case .tooLarge:
            return String(format: L("This image is too large. Choose an image under %d MB."),
                          AppAppearanceValidatedImage.maximumBytes / (1024 * 1024))
        case .unsupportedFormat: return L("This image format is not supported. Use PNG, JPEG, or HEIC.")
        case .undecodable: return L("This image could not be used. Choose another image.")
        case .dimensionsTooLarge:
            return String(format: L("This image is too large in pixels. Choose an image up to %d pixels on its longest side."),
                          AppAppearanceValidatedImage.maximumDimension)
        }
    }
}

/// The crop applied to a preview image before it is shown. The rect is
/// computed from the real pixel size, so a crop is never guessed from a
/// thumbnail. All insets are fractions of the image size, clamped to
/// 0...0.4, and the result always keeps at least one pixel.
struct AppAppearanceCrop: Equatable, Codable, Sendable {
    enum Mode: String, Equatable, Codable, Sendable {
        case full
        case square
        case custom
    }

    var mode: Mode = .full
    var top: CGFloat = 0
    var leading: CGFloat = 0
    var bottom: CGFloat = 0
    var trailing: CGFloat = 0

    /// The uniform inset when all four sides agree, otherwise their
    /// average. The UI edits a single uniform inset; per-side values stay
    /// available for drafts and future editing.
    var uniformInset: CGFloat { (top + leading + bottom + trailing) / 4 }

    /// The crop rect in the image's own pixel coordinates.
    func rect(for size: CGSize) -> CGRect {
        let width = max(1, size.width), height = max(1, size.height)
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        switch mode {
        case .full:
            return bounds
        case .square:
            let side = min(width, height)
            return CGRect(x: (width - side) / 2, y: (height - side) / 2, width: side, height: side)
        case .custom:
            let rect = CGRect(x: clamp(leading) * width, y: clamp(top) * height,
                              width: max(1, width * (1 - clamp(leading) - clamp(trailing))),
                              height: max(1, height * (1 - clamp(top) - clamp(bottom))))
            return rect.intersection(bounds)
        }
    }

    private func clamp(_ value: CGFloat) -> CGFloat { min(0.4, max(0, value)) }
}

/// One preview state: the imported image bytes (if any), the proposed name,
/// the crop, and the corner radius. This is the unit of undo history and
/// of draft saving. It never touches the installed app.
struct AppAppearancePreviewState: Equatable, Codable, Sendable {
    var imageData: Data?
    var name: String
    var crop: AppAppearanceCrop
    var cornerRadius: CGFloat

    static let maximumCornerRadius: CGFloat = 27
    static let empty = AppAppearancePreviewState()

    init(imageData: Data? = nil, name: String = "", crop: AppAppearanceCrop = AppAppearanceCrop(), cornerRadius: CGFloat = 12) {
        self.imageData = imageData
        self.name = name
        self.crop = crop
        self.cornerRadius = min(Self.maximumCornerRadius, max(0, cornerRadius))
    }
}

/// Undo history for the preview. The stack holds every distinct state;
/// undo returns to the previous one. The first entry is always the empty
/// state, so undo can never go below "nothing imported".
struct AppAppearancePreviewHistory: Equatable, Sendable {
    private(set) var states: [AppAppearancePreviewState] = [.empty]

    var current: AppAppearancePreviewState { states.last ?? .empty }
    var canUndo: Bool { states.count > 1 }

    mutating func push(_ state: AppAppearancePreviewState) {
        guard state != current else { return }
        states.append(state)
    }

    /// Updates the current state in place without adding a history entry.
    /// Used for continuous edits (typing a name) that must not flood the
    /// undo stack; discrete actions use `push`.
    mutating func updateCurrent(_ transform: (inout AppAppearancePreviewState) -> Void) {
        guard !states.isEmpty else { return }
        transform(&states[states.count - 1])
    }

    /// Removes the current state and returns the new current one, or nil
    /// when there is nothing to undo.
    mutating func undo() -> AppAppearancePreviewState? {
        guard states.count > 1 else { return nil }
        states.removeLast()
        return states.last
    }

    mutating func reset() { states = [.empty] }
}

/// A locally saved preview draft. It lives only in LilaShift's own
/// container, never in the target app's container, and it records a
/// SHA-256 digest of the image bytes so a tampered or truncated draft is
/// refused instead of shown.
struct AppAppearanceDraft: Equatable, Codable, Sendable {
    var version: Int
    var bundleID: String
    var state: AppAppearancePreviewState
    var imageDigest: String
    var savedAt: Date

    init(bundleID: String, state: AppAppearancePreviewState, savedAt: Date = Date()) {
        self.version = 1
        self.bundleID = bundleID
        self.state = state
        self.imageDigest = state.imageData.map { CustomizationFiles.digest($0) } ?? ""
        self.savedAt = savedAt
    }

    /// Saves this draft under the app's own container directory.
    /// The bundle ID must already be validated (it comes from the catalog).
    func save(to directory: URL) throws {
        guard LaunchArtworkDirectory.validIdentifier(bundleID) else {
            throw CustomizationFailure("The archive is invalid or exceeds the size limit.")
        }
        try CustomizationFiles.saveVerified(self, to: directory.appendingPathComponent(bundleID + ".plist"))
    }

    /// Loads the draft for a bundle ID, or nil when none was saved.
    /// Throws when the file exists but is corrupt, foreign, or tampered.
    static func load(bundleID: String, from directory: URL) throws -> AppAppearanceDraft? {
        guard LaunchArtworkDirectory.validIdentifier(bundleID) else {
            throw CustomizationFailure("The archive is invalid or exceeds the size limit.")
        }
        let url = directory.appendingPathComponent(bundleID + ".plist")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let draft = try PropertyListDecoder().decode(AppAppearanceDraft.self, from: CustomizationFiles.read(url))
        guard draft.version == 1, draft.bundleID == bundleID,
              draft.imageDigest == (draft.state.imageData.map { CustomizationFiles.digest($0) } ?? "") else {
            throw CustomizationFailure("The archive is invalid or exceeds the size limit.")
        }
        return draft
    }

    static func hasDraft(bundleID: String, in directory: URL) -> Bool {
        guard LaunchArtworkDirectory.validIdentifier(bundleID) else { return false }
        return FileManager.default.fileExists(atPath: directory.appendingPathComponent(bundleID + ".plist").path)
    }
}

// MARK: - Gated icon-cache write path (3.1, 七猫小说 first target)
//
// The probe is read-only and a match is only a *candidate* record: it is
// NOT proof the Home Screen uses that record. Nothing here writes until
// `IconCacheWriteGate` says the evidence qualifies, and a write only
// becomes verified-effective after `IconCacheWritePlan.verifyAfterRestart`
// sees a real reboot plus a fresh probe that still shows the mutation.
// The probe never computes a full-file hash (it reads at most a 128 KB
// prefix for matching), so `sha256AtProbe` is the SHA-256 of that probed
// prefix, and the write/read-back guards compare the same prefix window.

/// A candidate icon-cache record: one matched file from a read-only
/// probe. "Candidate" is deliberate — this is not proof the Home Screen
/// uses the record, and it must never be presented as effective.
struct VerifiedIconCacheRecord: Codable, Equatable, Sendable {
    let bundleID: String
    /// Absolute path of the cache root that contained the match.
    let cacheRoot: String
    /// File path relative to the cache root, as reported by the probe.
    let relativePath: String
    let size: Int
    let inode: UInt64
    /// SHA-256 of the probed prefix (at most the first 128 KB), taken at
    /// probe time. The write path compares the same prefix window, never
    /// a full-file hash the probe never computed.
    let sha256AtProbe: String
    /// SHA-256 of the LaunchServices cache at probe time, when known.
    /// Binds the record to the cache generation the probe saw.
    let probedCacheSHA: String?

    /// Builds a record only from evidence probed for this bundle ID that
    /// contains at least one match with a probed prefix hash. Returns nil
    /// otherwise (no match, or a match whose prefix could not be read).
    static func fromEvidence(_ evidence: DiskIconCacheEvidence, bundleID: String,
                             probedCacheSHA: String? = nil) -> Self? {
        guard evidence.bundleID == bundleID,
              let match = evidence.matchesDetail.first,
              let prefixSHA = match.prefixSHA256 else { return nil }
        return Self(bundleID: bundleID, cacheRoot: match.root, relativePath: match.file,
                    size: match.bytes, inode: match.inode, sha256AtProbe: prefixSHA,
                    probedCacheSHA: probedCacheSHA)
    }
}

enum IconCacheWriteGateResult: Equatable, Sendable {
    case blocked(reason: String)
    case ready(record: VerifiedIconCacheRecord)
}

/// The gate in front of every icon-cache write. The first implementation
/// accepts only 七猫小说; any other bundle ID is blocked.
enum IconCacheWriteGate {
    /// The only bundle ID in scope for the first write target. WeChat and
    /// Alipay follow after 七猫小说 verification.
    static let firstWriteTargetBundleID = "com.yueyou.cyreader"
    static let iconCacheGroupPath = "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.lsd.iconscache"
    /// The probe reads at most this many leading bytes of a matched file
    /// for matching; the probed hash covers exactly that prefix.
    static let probedPrefixLimit = 128 * 1024

    static func evaluate(_ evidence: DiskIconCacheEvidence, bundleID: String,
                         probedCacheSHA: String? = nil) -> IconCacheWriteGateResult {
        guard bundleID == firstWriteTargetBundleID else {
            // WeChat/Alipay follow after 七猫小说 verification.
            return .blocked(reason: appearanceDiagnosticText("Only 七猫小说 is in scope for the first write target."))
        }
        guard let record = VerifiedIconCacheRecord.fromEvidence(evidence, bundleID: bundleID,
                                                                probedCacheSHA: probedCacheSHA) else {
            if evidence.matchesDetail.isEmpty {
                return .blocked(reason: appearanceDiagnosticText("No candidate record matches this app."))
            }
            return .blocked(reason: appearanceDiagnosticText("The candidate record has no probed content hash."))
        }
        return .ready(record: record)
    }

    /// Icon replacement is refused until a probe confirms the icon bytes.
    /// There is no code path that writes icon bytes.
    static func evaluateIconReplacement() -> IconCacheWriteGateResult {
        .blocked(reason: appearanceDiagnosticText("Icon record format not confirmed"))
    }
}

enum WriteMutationFailure: Error, Equatable, Sendable {
    case invalidName
    case notFound
    case ambiguous
    case lengthMismatch
}

/// One byte-level edit inside a matched cache-file prefix: replace
/// `length` bytes at `offset` with `replacement` (always the same length,
/// so the file size and every other offset stay unchanged).
struct WriteMutation: Codable, Equatable, Sendable {
    let offset: Int
    let length: Int
    let replacement: Data

    /// Builds the first supported mutation: replace the current display
    /// name's bytes with a new name's bytes, in UTF-8 or UTF-16LE form,
    /// inside the matched prefix only. It succeeds only when the current
    /// name occurs exactly once across both forms, the new name encodes
    /// to the same byte length in that form, and the new name is valid
    /// (non-empty, at most 32 characters, no control characters).
    /// Icon bytes are never mutated here; see
    /// `IconCacheWriteGate.evaluateIconReplacement`.
    static func displayNameReplacement(prefix: Data, currentName: String,
                                       newName: String) -> Result<WriteMutation, WriteMutationFailure> {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 32,
              !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            return .failure(.invalidName)
        }
        guard let currentUTF8 = currentName.data(using: .utf8),
              let currentUTF16 = currentName.data(using: .utf16LittleEndian),
              let newUTF8 = trimmed.data(using: .utf8),
              let newUTF16 = trimmed.data(using: .utf16LittleEndian),
              !currentUTF8.isEmpty else { return .failure(.notFound) }
        var found: WriteMutation?
        var occurrences = 0
        var anyLengthCompatible = false
        for (current, replacement) in [(currentUTF8, newUTF8), (currentUTF16, newUTF16)] {
            // A form whose lengths differ cannot be replaced in place.
            guard current.count == replacement.count else { continue }
            anyLengthCompatible = true
            var searchRange = prefix.startIndex..<prefix.endIndex
            while let range = prefix.range(of: current, options: [], in: searchRange) {
                occurrences += 1
                if occurrences == 1 {
                    found = WriteMutation(offset: range.lowerBound, length: current.count, replacement: replacement)
                }
                if occurrences > 1 { return .failure(.ambiguous) }
                searchRange = range.upperBound..<prefix.endIndex
            }
        }
        if let mutation = found, occurrences == 1 { return .success(mutation) }
        return .failure(anyLengthCompatible ? .notFound : .lengthMismatch)
    }

    /// Returns `data` with this mutation applied, or nil when the
    /// mutation lies outside `data`.
    func applied(to data: Data) -> Data? {
        guard offset >= 0, length == replacement.count, length > 0,
              offset + length <= data.count else { return nil }
        var result = data
        result.replaceSubrange(offset..<(offset + length), with: replacement)
        return result
    }

    /// SHA-256 of the prefix after this mutation, for read-back comparison.
    func expectedSHA(afterApplyingTo prefix: Data) -> String? {
        applied(to: prefix).map { CustomizationFiles.digest($0) }
    }
}

enum IconCacheWriteError: Error, Equatable, Sendable {
    case notBackedUp
    case backupMissing
    case unexpectedMatchCount(Int)
    case shaMismatch
    case mutationFailed(WriteMutationFailure)
    case readBackMismatch
    case restoreFailed
    case invalidState
    case fileUnavailable
}

extension IconCacheWriteError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notBackedUp:
            return appearanceDiagnosticText("A backup is required before writing.")
        case .backupMissing:
            return appearanceDiagnosticText("The backup is missing or does not match.")
        case .unexpectedMatchCount:
            return appearanceDiagnosticText("More than one candidate record matches. Only a single record can be written.")
        case .shaMismatch:
            return appearanceDiagnosticText("The cache file changed since the probe. Read again before writing.")
        case .mutationFailed(let failure):
            switch failure {
            case .invalidName:
                return appearanceDiagnosticText("The new display name is invalid.")
            case .notFound:
                return appearanceDiagnosticText("The current display name was not found in the matched prefix.")
            case .ambiguous:
                return appearanceDiagnosticText("The display name occurs more than once in the matched prefix.")
            case .lengthMismatch:
                return appearanceDiagnosticText("The display name must encode to the same byte length as the current name.")
            }
        case .readBackMismatch:
            return appearanceDiagnosticText("Read-back did not match the expected bytes. The backup was restored.")
        case .restoreFailed:
            return appearanceDiagnosticText("The backup could not be restored. The backup has been kept.")
        case .invalidState:
            return appearanceDiagnosticText("The write plan is not in the expected state.")
        case .fileUnavailable:
            return appearanceDiagnosticText("The icon cache could not be opened for writing.")
        }
    }
}

/// The gated write state machine. The only forward path is
/// idle -> backedUp -> written -> readBackVerified ->
/// awaitingRestartVerification -> verifiedAfterRestart. Any state may go
/// to restored (backup copied back and verified) or failed. The write
/// action stops at awaitingRestartVerification: it never auto-restores
/// and never claims the change is effective before the restart check.
struct IconCacheWritePlan: Codable, Equatable, Sendable {
    enum State: String, Codable, Equatable, Sendable {
        case idle
        case backedUp
        case written
        case readBackVerified
        case awaitingRestartVerification
        case verifiedAfterRestart
        case restored
        case failed
    }

    var state: State = .idle
    var record: VerifiedIconCacheRecord?
    var mutation: WriteMutation?
    var backupSHA256: String?
    var expectedPostWriteSHA256: String?
    var preWriteBootSession: BootSession?
    var writtenAt: Date?
    var failureReason: String?

    // MARK: Storage in the app's own container (AppAppearanceDraft-style)

    /// Per-app backup directory under Application Support. The backup
    /// bytes and this plan's plist live here, never in the cache root.
    static func backupDirectory(for bundleID: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GestaltX/AppAppearance/IconCacheBackups/\(bundleID)", isDirectory: true)
    }

    static func backupFileURL(in backupDirectory: URL) -> URL {
        backupDirectory.appendingPathComponent("backup.bin")
    }

    static func planFileURL(in backupDirectory: URL) -> URL {
        backupDirectory.appendingPathComponent("plan.plist")
    }

    /// Persists this plan (PropertyList, verified round-trip) so the
    /// awaiting-restart state survives an app relaunch.
    func save(to backupDirectory: URL) throws {
        try CustomizationFiles.saveVerified(self, to: Self.planFileURL(in: backupDirectory))
    }

    static func load(from backupDirectory: URL) throws -> Self? {
        let url = planFileURL(in: backupDirectory)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try PropertyListDecoder().decode(Self.self, from: CustomizationFiles.read(url))
    }

    // MARK: File access (confined to the cache root and the backup directory)

    private static func cacheFileURL(cacheRoot: URL, record: VerifiedIconCacheRecord) throws -> URL {
        // CustomizationFiles.checked rejects "..", absolute paths and any
        // symlink component, so the resolved file stays inside the root.
        try CustomizationFiles.checked(record.relativePath, in: cacheRoot)
    }

    private static func inode(of url: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let number = attributes[.systemFileNumber] as? NSNumber else {
            throw IconCacheWriteError.fileUnavailable
        }
        return number.uint64Value
    }

    private static func backupIsValid(backupDirectory: URL, expectedSHA: String) -> Bool {
        guard let backup = try? CustomizationFiles.read(backupFileURL(in: backupDirectory)) else { return false }
        return CustomizationFiles.digest(backup) == expectedSHA
    }

    /// Copies the matched file's bytes into the app's own backup
    /// directory and records the SHA-256 before and after the copy. The
    /// backup is kept until a restore is verified; the plan never
    /// deletes it.
    mutating func backup(cacheRoot: URL, backupDirectory: URL, record: VerifiedIconCacheRecord) throws {
        guard state == .idle || state == .restored else { throw IconCacheWriteError.invalidState }
        let url = try Self.cacheFileURL(cacheRoot: cacheRoot, record: record)
        let bytes = try CustomizationFiles.read(url)
        let inode = try Self.inode(of: url)
        guard bytes.count == record.size, inode == record.inode else {
            throw IconCacheWriteError.shaMismatch
        }
        let sha = CustomizationFiles.digest(bytes)
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        try bytes.write(to: Self.backupFileURL(in: backupDirectory), options: .atomic)
        guard Self.backupIsValid(backupDirectory: backupDirectory, expectedSHA: sha) else {
            throw IconCacheWriteError.backupMissing
        }
        self.record = record
        backupSHA256 = sha
        mutation = nil
        expectedPostWriteSHA256 = nil
        preWriteBootSession = nil
        writtenAt = nil
        failureReason = nil
        state = .backedUp
    }

    /// Writes the display-name mutation in place (same byte length, same
    /// inode, same file size). Single-item only: refuses unless the fresh
    /// evidence has exactly one match for the recorded file, a valid
    /// backup exists, and the current prefix hash still equals the probed
    /// hash (TOCTOU guard). Records the boot session from before the
    /// write so the restart check can prove a reboot happened.
    mutating func write(cacheRoot: URL, backupDirectory: URL, evidence: DiskIconCacheEvidence,
                        currentName: String, newName: String, bootBefore: BootSession?) throws {
        guard state == .backedUp, let record else { throw IconCacheWriteError.notBackedUp }
        guard let backupSHA256, Self.backupIsValid(backupDirectory: backupDirectory, expectedSHA: backupSHA256) else {
            throw IconCacheWriteError.backupMissing
        }
        guard evidence.matchesDetail.count == 1,
              evidence.matchesDetail.first?.file == record.relativePath else {
            throw IconCacheWriteError.unexpectedMatchCount(evidence.matchesDetail.count)
        }
        let url = try Self.cacheFileURL(cacheRoot: cacheRoot, record: record)
        let bytes = try CustomizationFiles.read(url)
        guard bytes.count == record.size else { throw IconCacheWriteError.shaMismatch }
        let prefix = Data(bytes.prefix(IconCacheWriteGate.probedPrefixLimit))
        guard CustomizationFiles.digest(prefix) == record.sha256AtProbe else {
            throw IconCacheWriteError.shaMismatch
        }
        let mutation: WriteMutation
        switch WriteMutation.displayNameReplacement(prefix: prefix, currentName: currentName, newName: newName) {
        case .success(let built):
            mutation = built
        case .failure(let failure):
            throw IconCacheWriteError.mutationFailed(failure)
        }
        guard let expected = mutation.expectedSHA(afterApplyingTo: prefix) else {
            throw IconCacheWriteError.mutationFailed(.notFound)
        }
        do {
            // In-place, inode-preserving write of only the replaced
            // bytes. The file size never changes.
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(mutation.offset))
            try handle.write(contentsOf: mutation.replacement)
            try handle.synchronize()
        } catch {
            // A partial in-place write must not be left behind.
            if (try? restore(cacheRoot: cacheRoot, backupDirectory: backupDirectory)) != nil {
                throw IconCacheWriteError.fileUnavailable
            }
            state = .failed
            failureReason = IconCacheWriteError.restoreFailed.errorDescription
            throw IconCacheWriteError.restoreFailed
        }
        self.mutation = mutation
        expectedPostWriteSHA256 = expected
        preWriteBootSession = bootBefore
        writtenAt = Date()
        state = .written
    }

    /// Re-reads the file and verifies the mutation bytes are present and
    /// the prefix hash equals the expected post-write hash. On mismatch
    /// the backup is restored immediately and the failure is reported.
    mutating func readBack(cacheRoot: URL, backupDirectory: URL) throws {
        guard state == .written, let record, let mutation, let expectedPostWriteSHA256 else {
            throw IconCacheWriteError.invalidState
        }
        let url = try Self.cacheFileURL(cacheRoot: cacheRoot, record: record)
        let bytes = try CustomizationFiles.read(url)
        let prefix = Data(bytes.prefix(IconCacheWriteGate.probedPrefixLimit))
        let offset = mutation.offset, length = mutation.length
        guard bytes.count == record.size, offset >= 0, offset + length <= bytes.count,
              bytes[offset..<(offset + length)] == mutation.replacement,
              CustomizationFiles.digest(prefix) == expectedPostWriteSHA256 else {
            try restore(cacheRoot: cacheRoot, backupDirectory: backupDirectory)
            throw IconCacheWriteError.readBackMismatch
        }
        state = .readBackVerified
    }

    /// Stops after a verified read-back: the change is a candidate until
    /// a restart proves it effective. This never auto-restores.
    mutating func beginRestartWait() throws {
        guard state == .readBackVerified else { throw IconCacheWriteError.invalidState }
        state = .awaitingRestartVerification
    }

    /// Copies the backup bytes back in place and verifies the SHA equals
    /// the pre-write SHA. The backup is kept until this verification
    /// succeeds, and is not deleted by the plan afterwards.
    @discardableResult
    mutating func restore(cacheRoot: URL, backupDirectory: URL) throws -> Self {
        guard state != .idle, let record, let backupSHA256 else {
            throw IconCacheWriteError.invalidState
        }
        guard let backup = try? CustomizationFiles.read(Self.backupFileURL(in: backupDirectory)),
              CustomizationFiles.digest(backup) == backupSHA256 else {
            state = .failed
            failureReason = IconCacheWriteError.backupMissing.errorDescription
            throw IconCacheWriteError.backupMissing
        }
        let url = try Self.cacheFileURL(cacheRoot: cacheRoot, record: record)
        do {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seek(toOffset: 0)
            try handle.write(contentsOf: backup)
            try handle.synchronize()
            // Drop any tail if the live file grew since the backup.
            try handle.truncate(atOffset: UInt64(backup.count))
        } catch {
            state = .failed
            failureReason = IconCacheWriteError.restoreFailed.errorDescription
            throw IconCacheWriteError.restoreFailed
        }
        let restored = try CustomizationFiles.read(url)
        guard CustomizationFiles.digest(restored) == backupSHA256 else {
            state = .failed
            failureReason = IconCacheWriteError.restoreFailed.errorDescription
            throw IconCacheWriteError.restoreFailed
        }
        mutation = nil
        expectedPostWriteSHA256 = nil
        state = .restored
        return self
    }

    /// Marks the change verified-effective ONLY when the device actually
    /// rebooted after the write AND a fresh probe still shows the mutated
    /// prefix. `bootChanged` must come from `RestartEvidence.compare`
    /// on the boot session recorded before the write. Until then the plan
    /// stays "awaiting restart verification".
    @discardableResult
    mutating func verifyAfterRestart(newEvidence: DiskIconCacheEvidence, bootChanged: Bool) -> Bool {
        guard state == .awaitingRestartVerification,
              bootChanged,
              let record, let expectedPostWriteSHA256,
              newEvidence.bundleID == record.bundleID else { return false }
        guard let fresh = newEvidence.matchesDetail.first(where: { $0.file == record.relativePath }),
              fresh.prefixSHA256 == expectedPostWriteSHA256 else { return false }
        state = .verifiedAfterRestart
        return true
    }
}
