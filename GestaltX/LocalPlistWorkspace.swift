// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// A local copy only. No stored path points back to the imported source or to a system file.
struct LocalPlistWorkspace {
    enum Failure: Error, Equatable {
        case unsupportedFile, tooLarge, notDictionary, staleRevision, damagedRecord, noChange
    }

    struct Record: Codable, Identifiable, Equatable, Sendable {
        let id: UUID
        let name: String
        let original: Data
        let originalSHA: String
        var working: Data
        var workingSHA: String
        var previous: Data? = nil
        var previousSHA: String? = nil
    }

    struct Change: Equatable {
        let recordID: UUID
        let beforeSHA: String
        let afterSHA: String
        let changedKeys: [String]
        let bytes: Data
    }

    static let maxBytes = 1_048_576
    let root: URL

    static func readSelectedFile(_ url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw Failure.unsupportedFile }
        if let size = values.fileSize, size > maxBytes { throw Failure.tooLarge }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var bytes = Data()
        while bytes.count <= maxBytes {
            let count = min(32_768, maxBytes + 1 - bytes.count)
            guard let chunk = try handle.read(upToCount: count), !chunk.isEmpty else { return bytes }
            bytes.append(chunk)
        }
        throw Failure.tooLarge
    }

    func importCopy(_ data: Data, name: String) throws -> Record {
        _ = try Self.dictionary(data)
        let digest = Self.sha(data)
        let created = Record(
            id: UUID(), name: String(name.prefix(100)), original: data, originalSHA: digest,
            working: data, workingSHA: digest
        )
        return try persistAndReadBack(created)
    }

    func records() throws -> [Record] {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let urls = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        return try urls
            .filter { $0.pathExtension == "json" }
            .compactMap { UUID(uuidString: $0.deletingPathExtension().lastPathComponent) }
            .map { try read($0) }
            .sorted { ($0.name, $0.id.uuidString) < ($1.name, $1.id.uuidString) }
    }

    func stage(xml: String, for record: Record) throws -> Change {
        let candidate = Data(xml.utf8)
        let before = try Self.dictionary(record.working)
        let after = try Self.dictionary(candidate)
        let changed = try Set(before.keys).union(after.keys).sorted().filter {
            try Self.encodedValue(before[$0]) != Self.encodedValue(after[$0])
        }
        guard !changed.isEmpty else { throw Failure.noChange }
        return Change(
            recordID: record.id, beforeSHA: record.workingSHA, afterSHA: Self.sha(candidate),
            changedKeys: changed, bytes: candidate
        )
    }

    func apply(_ change: Change) throws -> Record {
        var current = try read(change.recordID)
        guard current.workingSHA == change.beforeSHA else { throw Failure.staleRevision }
        _ = try Self.dictionary(change.bytes)
        guard Self.sha(change.bytes) == change.afterSHA else { throw Failure.damagedRecord }
        current.previous = current.working
        current.previousSHA = current.workingSHA
        current.working = change.bytes
        current.workingSHA = change.afterSHA
        return try persistAndReadBack(current)
    }

    func restoreOriginal(id: UUID, expectedSHA: String) throws -> Record {
        var current = try read(id)
        guard current.workingSHA == expectedSHA else { throw Failure.staleRevision }
        current.previous = current.working
        current.previousSHA = current.workingSHA
        current.working = current.original
        current.workingSHA = current.originalSHA
        return try persistAndReadBack(current)
    }

    func restorePrevious(id: UUID, expectedSHA: String) throws -> Record {
        var current = try read(id)
        guard current.workingSHA == expectedSHA else { throw Failure.staleRevision }
        guard let before = current.previous, let digest = current.previousSHA else { throw Failure.noChange }
        current.previous = current.working
        current.previousSHA = current.workingSHA
        current.working = before
        current.workingSHA = digest
        return try persistAndReadBack(current)
    }

    static func editableXML(_ data: Data) throws -> String {
        let bytes = try PropertyListSerialization.data(fromPropertyList: dictionary(data), format: .xml, options: 0)
        guard bytes.count <= maxBytes else { throw Failure.tooLarge }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func dictionary(_ data: Data) throws -> [String: Any] {
        guard data.count <= maxBytes else { throw Failure.tooLarge }
        guard let values = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw Failure.notDictionary
        }
        return values
    }

    private static func encodedValue(_ value: Any?) throws -> Data? {
        guard let value else { return nil }
        return try PropertyListSerialization.data(fromPropertyList: [value], format: .xml, options: 0)
    }

    private static func sha(_ bytes: Data) -> String {
        // ADR-2-08: BackupEngine owns the only SHA-256 implementation.
        BackupEngine.sha256Hex(of: bytes)
    }

    private func persistAndReadBack(_ record: Record) throws -> Record {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let payload = try JSONEncoder().encode(record)
#if os(iOS)
        try payload.write(to: path(record.id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
#else
        try payload.write(to: path(record.id), options: [.atomic])
#endif
        let verified = try read(record.id)
        guard verified == record else { throw Failure.damagedRecord }
        return verified
    }

    private func read(_ id: UUID) throws -> Record {
        let url = path(id)
        let props = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard props.isRegularFile == true, props.isSymbolicLink != true,
              let size = props.fileSize, size <= 6 * Self.maxBytes else { throw Failure.damagedRecord }
        let value = try JSONDecoder().decode(Record.self, from: Data(contentsOf: url))
        guard value.id == id, value.original.count <= Self.maxBytes, value.working.count <= Self.maxBytes,
              Self.sha(value.original) == value.originalSHA, Self.sha(value.working) == value.workingSHA
        else { throw Failure.damagedRecord }
        switch (value.previous, value.previousSHA) {
        case (nil, nil): break
        case (let before?, let digest?) where before.count <= Self.maxBytes && Self.sha(before) == digest: break
        default: throw Failure.damagedRecord
        }
        return value
    }

    private func path(_ id: UUID) -> URL { root.appendingPathComponent("\(id.uuidString).json", isDirectory: false) }
}
