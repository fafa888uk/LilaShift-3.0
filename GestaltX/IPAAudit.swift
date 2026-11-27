// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import ZIPFoundation

struct IPAAudit: Sendable {
    let bundleID: String?
    let version: String?
    let minimumOS: String?
    let executablePresent: Bool
    let signatureResourcesPresent: Bool
    let provisioningPresent: Bool
    let codePaths: [String]
    let usageDescriptionKeys: [String]

    private static let maximumEntries = 30_000
    private static let maximumPlistBytes = 1024 * 1024

    static func inspect(_ url: URL) throws -> Self {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let archive = try Archive(url: url, accessMode: .read)
        var paths = Set<String>()
        var regularFiles = Set<String>()
        var rootPlists: [Entry] = []
        var codePaths: [String] = []
        for entry in archive {
            try Task.checkCancellation()
            let path = entry.path.hasSuffix("/") ? String(entry.path.dropLast()) : entry.path
            _ = try CustomizationFiles.relative(path)
            guard paths.count < maximumEntries, entry.type != .symlink, paths.insert(path).inserted else {
                throw CustomizationFailure("The archive contains unsafe paths or links.")
            }
            if entry.type == .file { regularFiles.insert(path) }
            let parts = path.split(separator: "/")
            if entry.type == .file, parts.count == 3, parts[0] == "Payload",
               parts[1].hasSuffix(".app"), parts[2] == "Info.plist" {
                rootPlists.append(entry)
            }
            if entry.type == .file, path.hasSuffix(".dylib") {
                codePaths.append(path)
            } else if let component = parts.last, parts.count > 1,
                      entry.type == .file, parts[parts.count - 2] == String(component) + ".framework" {
                codePaths.append(path)
            }
        }
        guard rootPlists.count == 1, let entry = rootPlists.first,
              entry.uncompressedSize <= UInt64(maximumPlistBytes) else {
            throw CustomizationFailure("The IPA must contain one app with a readable Info.plist.")
        }
        var data = Data()
        let crc = try archive.extract(entry, bufferSize: 64 * 1024) { chunk in
            try Task.checkCancellation()
            guard chunk.count <= maximumPlistBytes - data.count else {
                throw CustomizationFailure("The archive is invalid or exceeds the size limit.")
            }
            data.append(chunk)
        }
        guard crc == entry.checksum, UInt64(data.count) == entry.uncompressedSize,
              let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw CustomizationFailure("The IPA must contain one app with a readable Info.plist.")
        }

        let root = String(entry.path.dropLast("Info.plist".count))
        let executable = plist["CFBundleExecutable"] as? String
        let executablePresent = executable.map { name in
            guard !name.isEmpty, !name.contains("/"), name != ".", name != ".." else { return false }
            return regularFiles.contains(root + name)
        } ?? false
        return Self(
            bundleID: plist["CFBundleIdentifier"] as? String,
            version: plist["CFBundleShortVersionString"] as? String,
            minimumOS: plist["MinimumOSVersion"] as? String,
            executablePresent: executablePresent,
            signatureResourcesPresent: regularFiles.contains(root + "_CodeSignature/CodeResources"),
            provisioningPresent: regularFiles.contains(root + "embedded.mobileprovision"),
            codePaths: codePaths.filter { $0.hasPrefix(root) }.sorted(),
            usageDescriptionKeys: plist.keys.filter { $0.hasSuffix("UsageDescription") }.sorted()
        )
    }
}
