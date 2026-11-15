// SPDX-License-Identifier: GPL-3.0-only
import Darwin
import Foundation

/// File identity from the descriptor that supplied the cache bytes.
struct CacheFileIdentity: Codable, Equatable, Sendable {
    let inode: UInt64
    let birthSeconds: Int64
    let birthMicroseconds: Int64

    static func read(descriptor: Int32) -> Self? {
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_birthtimespec.tv_sec > 0 else { return nil }
        return Self(inode: UInt64(info.st_ino), birthSeconds: Int64(info.st_birthtimespec.tv_sec),
                    birthMicroseconds: Int64(info.st_birthtimespec.tv_nsec / 1_000))
    }
}

struct CacheFingerprint: Codable, Equatable, Sendable {
    let cacheUUID: String?
    let fileSHA256: String
    let fileSize: Int
    let cacheDataLength: Int?
    let layout: MobileGestaltCacheLayout?
    let productType: String?
    let osBuild: String?
    let fileIdentity: CacheFileIdentity?

    init(snapshot: DocumentSnapshot, osBuild: String?) {
        cacheUUID = snapshot.document.cacheUUID?.uppercased()
        fileSHA256 = GestaltFileStore.sha256Hex(of: snapshot.data)
        fileSize = snapshot.data.count
        cacheDataLength = (snapshot.document.root["CacheData"] as? Data)?.count
        layout = try? MobileGestaltCacheLayout.resolve(in: snapshot.document)
        productType = snapshot.document.extra[GestaltKeys.productType] as? String
        self.osBuild = osBuild
        fileIdentity = snapshot.cacheFileIdentity
    }

    var observedScope: String {
        [productType ?? L("Unknown"), osBuild ?? L("Unknown")].joined(separator: " / ")
    }

    func compare(to current: Self) -> CacheFingerprintComparison {
        let uuidChanged = cacheUUID != current.cacheUUID
        let bytesChanged = fileSHA256 != current.fileSHA256
        let knownLayoutChanged: Bool
        if let before = layout, let after = current.layout {
            knownLayoutChanged = before.slotCount != after.slotCount || before.greenTeaIndex != after.greenTeaIndex
                || before.notGreenTeaIndex != after.notGreenTeaIndex || before.wapiIndex != after.wapiIndex
                || before.audioIntellIndex != after.audioIntellIndex
                || before.personalTranslatorIndex != after.personalTranslatorIndex
        } else {
            knownLayoutChanged = false
        }
        let layoutChanged = cacheDataLength != current.cacheDataLength || knownLayoutChanged
        let fileReplaced = fileIdentity.flatMap { before in current.fileIdentity.map { before != $0 } }
        return CacheFingerprintComparison(
            uuidChanged: uuidChanged, bytesChanged: bytesChanged, layoutChanged: layoutChanged,
            layoutResolutionChanged: (layout == nil) != (current.layout == nil),
            fileReplaced: fileReplaced,
            rebuildEvidence: fileReplaced == true && bytesChanged && (uuidChanged || layoutChanged)
        )
    }
}

struct CacheFingerprintComparison: Equatable, Sendable {
    let uuidChanged: Bool
    let bytesChanged: Bool
    let layoutChanged: Bool
    let layoutResolutionChanged: Bool
    let fileReplaced: Bool?
    /// A replacement plus changed cache generation/shape supports a rebuild.
    /// The app cannot identify which process performed it.
    let rebuildEvidence: Bool
}

struct BootSession: Codable, Equatable, Sendable {
    let seconds: Int64
    let microseconds: Int64

    var startedAt: Date {
        Date(timeIntervalSince1970: Double(seconds) + Double(microseconds) / 1_000_000)
    }

    static func current() -> Self? {
        #if targetEnvironment(simulator)
        return nil
        #else
        var time = timeval()
        var size = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &time, &size, nil, 0) == 0,
              size == MemoryLayout<timeval>.size, time.tv_sec > 0 else { return nil }
        return Self(seconds: Int64(time.tv_sec), microseconds: Int64(time.tv_usec))
        #endif
    }
}

enum RestartEvidence: String, Equatable, Sendable {
    case noFreshRead, sameBoot, verifiedBootChange, manualWithFreshRead, unknown

    static func compare(before: BootSession?, after: BootSession?, referenceDate: Date,
                        readAt: Date?, manual: Bool) -> Self {
        guard let readAt, readAt > referenceDate else { return .noFreshRead }
        if let before, let after {
            if before == after { return .sameBoot }
            // A clock correction or a backwards jump is insufficient. The
            // new start must fall between the write and the actual device read.
            return after.startedAt > referenceDate && after.startedAt <= readAt ? .verifiedBootChange : .unknown
        }
        return manual ? .manualWithFreshRead : .unknown
    }

    var hasPostRestartRead: Bool { self == .verifiedBootChange || self == .manualWithFreshRead }

    var label: String {
        switch self {
        case .noFreshRead: L("Reconnect and read the device")
        case .sameBoot: L("Same system boot session")
        case .verifiedBootChange: L("Restart verified by system boot time")
        case .manualWithFreshRead: L("Manual restart report with a fresh device read")
        case .unknown: L("Restart evidence unavailable")
        }
    }
}

/// Binary plist encoding retains values outside the typed change journal's
/// subset, including the exact Siri configuration type. A missing value is explicit.
struct PlistObservation: Codable, Equatable, Sendable {
    let type: String
    let encodedValue: Data?

    init(_ value: Any?) {
        type = value.map { PlistValueKind.detect($0).rawValue } ?? "Absent"
        encodedValue = value.flatMap {
            try? PropertyListSerialization.data(fromPropertyList: [$0], format: .binary, options: 0)
        }
    }

    var value: Any? {
        guard let encodedValue,
              let container = try? PropertyListSerialization.propertyList(from: encodedValue, format: nil) as? [Any]
        else { return nil }
        return container.first
    }

    var display: String {
        if type == "Absent" { return L("Not set") }
        return value.map { "\(String(describing: $0)) (\(L(type)))" } ?? L("Unknown")
    }

    var capabilityBoolean: Bool? {
        guard let value else { return nil }
        switch ChangeValue.fromPlistValue(value) {
        case .bool(let flag): return flag
        case .int(0): return false
        case .int(1): return true
        default: return nil
        }
    }
}

struct DeviceBaseline: Codable, Equatable, Sendable {
    let productType: String
    let hardwareModel: String?
    let osVersion: String?
    let osBuild: String?
    let deviceLanguage: String?
    let siriLanguage: String?
    let availableStorage: Int64?
    let originalAIValues: [String: PlistObservation]
    let liveProbeResults: [String: PlistObservation]
    let fingerprint: CacheFingerprint
    let bootSession: BootSession?
    let capturedAt: Date
    let audioIntelligenceSlot: Bool?
    let personalTranslatorSlot: Bool?

    var cacheUUID: String? { fingerprint.cacheUUID }
    var cacheFileSHA256: String { fingerprint.fileSHA256 }
    var cacheFileSize: Int { fingerprint.fileSize }
    var originalValueTypes: [String: String] { originalAIValues.mapValues(\.type) }
}

struct DevicePersistenceRead {
    let snapshot: DocumentSnapshot
    let fingerprint: CacheFingerprint
    let bootSession: BootSession?
    let readAt: Date
    let liveProbeResults: [String: PlistObservation]
}

struct PersistenceWrite: Codable {
    let fingerprint: CacheFingerprint
    let bootSession: BootSession?
    let writtenAt: Date
    let records: [RecordedChange]
}

struct AIKeyDiagnostic: Identifiable {
    var id: String { key }
    let key: String
    let title: String
    let nativeHardware: Bool
    let original: PlistObservation
    let file: PlistObservation
    let live: PlistObservation?
    let target: ChangeValue?
    let postRestartFile: PlistObservation?
    let postRestartLive: PlistObservation?
    let status: AcceptanceStatus
    let observedScope: String
    let cacheDataSlot: Bool?
    let originalCacheDataSlot: Bool?
}
