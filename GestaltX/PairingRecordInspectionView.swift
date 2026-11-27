// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Security
import SwiftUI
import UniformTypeIdentifiers

struct PairingRecordInspection: Sendable {
    let missingIdentifiers: [String]
    let unreadableCertificates: [String]
    let missingKeys: [String]

    static func inspect(_ url: URL) throws -> Self {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let limit = 256 * 1024
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let fileSize = values.fileSize, fileSize <= limit else {
            throw CustomizationFailure("Choose a pairing record smaller than 256 KB.")
        }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        guard let data = try file.read(upToCount: limit + 1), data.count <= limit,
              let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw CustomizationFailure("This file does not contain a readable pairing record.")
        }

        let identifiers = ["HostID", "SystemBUID"].filter {
            (plist[$0] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        }
        let certificates = ["DeviceCertificate", "HostCertificate", "RootCertificate"].filter {
            guard let raw = plist[$0] as? Data else { return true }
            return !Self.canReadCertificate(raw)
        }
        let keys = ["HostPrivateKey", "RootPrivateKey"].filter {
            (plist[$0] as? Data)?.isEmpty ?? true
        }
        return Self(missingIdentifiers: identifiers, unreadableCertificates: certificates, missingKeys: keys)
    }

    private static func canReadCertificate(_ raw: Data) -> Bool {
        if SecCertificateCreateWithData(nil, raw as CFData) != nil { return true }
        guard let pem = String(data: raw, encoding: .utf8),
              pem.hasPrefix("-----BEGIN CERTIFICATE-----") else { return false }
        let base64 = pem.components(separatedBy: .newlines).filter { !$0.hasPrefix("-----") }.joined()
        guard let der = Data(base64Encoded: base64) else { return false }
        return SecCertificateCreateWithData(nil, der as CFData) != nil
    }
}

struct PairingRecordInspectionView: View {
    @State private var picking = false
    @State private var report: PairingRecordInspection?
    @State private var failure: String?

    var body: some View {
        List {
            Section {
                Button { picking = true } label: {
                    Label(L("Choose Pairing Record"), systemImage: "doc.badge.magnifyingglass")
                }
                if let failure { Text(failure).foregroundStyle(.secondary) }
            } footer: {
                Text(L("Checks a file locally without saving or displaying its private keys. A structural check cannot confirm whether an iPhone still trusts the pairing."))
            }
            if let report {
                Section(L("Pairing Record Checks")) {
                    check("Missing Identifiers", fields: report.missingIdentifiers)
                    check("Unreadable Certificates", fields: report.unreadableCertificates)
                    check("Missing Private Key Fields", fields: report.missingKeys)
                }
            }
        }
        .navigationTitle(L("Pairing Record Inspection"))
        .fileImporter(isPresented: $picking, allowedContentTypes: [.propertyList, .init(filenameExtension: "mobiledevicepairing") ?? .data]) { selection in
            report = nil
            failure = nil
            do {
                report = try PairingRecordInspection.inspect(selection.get())
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    private func check(_ title: String, fields: [String]) -> some View {
        LabeledContent(L(title), value: fields.isEmpty ? L("None Found") : fields.joined(separator: ", "))
    }
}
