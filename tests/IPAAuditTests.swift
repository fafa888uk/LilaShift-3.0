// SPDX-License-Identifier: GPL-3.0-only
// Tests for the W3 IPA security audit (LilaShift 5.0.0): Mach-O
// parsing, dual-slot CSBlob parsing, threat-catalog verdicts,
// the CVE radar's verification statuses, secure IPA scanning
// (Zip-Slip, decompression bomb, FairPlay skip), report export
// round-trips, and the W3 registration metadata.
//
// All fixtures are built in memory by the helpers below — no
// real IPA is bundled, and no finding is ever faked: every
// verdict asserted here comes from the real parser running over
// fixture bytes.
import Foundation
import XCTest
@testable import GestaltX

final class IPAAuditTests: XCTestCase {
    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("IPAAuditTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    // MARK: - Byte helpers

    private func u16le(_ value: UInt16) -> Data {
        var v = value.littleEndian
        return Data(bytes: &v, count: 2)
    }

    private func u32le(_ value: UInt32) -> Data {
        var v = value.littleEndian
        return Data(bytes: &v, count: 4)
    }

    private func u32be(_ value: UInt32) -> Data {
        var v = value.bigEndian
        return Data(bytes: &v, count: 4)
    }

    private func u64le(_ value: UInt64) -> Data {
        var v = value.littleEndian
        return Data(bytes: &v, count: 8)
    }

    private func fixedString(_ text: String, length: Int) -> Data {
        var data = Data(text.utf8)
        if data.count > length {
            data = data.subdata(in: 0..<length)
        }
        data.append(Data(count: length - data.count))
        return data
    }

    // MARK: - Mach-O fixture builder

    /// Builds a minimal valid thin Mach-O with a __TEXT segment
    /// (__text, __cstring, __objc_methname), LC_SYMTAB, one
    /// LC_LOAD_DYLIB per `dylibs` entry, LC_ENCRYPTION_INFO(_64)
    /// and, when given, LC_CODE_SIGNATURE.
    private func makeMachO(
        symbols: [String] = [],
        dylibs: [String] = [],
        cstrings: [String] = [],
        selectors: [String] = [],
        cryptid: UInt32 = 0,
        codeSignature: Data? = nil,
        includeSvc: Bool = false,
        cputype: UInt32 = 0x0100_000C,
        cpuSubtype: UInt32 = 0,
        is64Bit: Bool = true
    ) -> Data {
        let headerSize = is64Bit ? 32 : 28
        var textBytes = Data(count: 16)
        if includeSvc {
            // ARM64 `svc #0x80` = 0xD4001001, little-endian.
            textBytes[0] = 0x01
            textBytes[1] = 0x10
            textBytes[2] = 0x00
            textBytes[3] = 0xD4
        }
        func joined(_ strings: [String]) -> Data {
            var data = Data()
            for string in strings {
                data.append(contentsOf: string.utf8)
                data.append(0)
            }
            if data.isEmpty { data.append(0) }
            return data
        }
        let cstringBytes = joined(cstrings)
        let methnameBytes = joined(selectors)

        var strtab = Data([0])
        var strOffsets: [Int] = []
        for symbol in symbols {
            strOffsets.append(strtab.count)
            strtab.append(contentsOf: symbol.utf8)
            strtab.append(0)
        }

        let sectionCount = 3
        let sectionSize = is64Bit ? 80 : 68
        let segmentCmdSize = (is64Bit ? 72 : 56) + sectionCount * sectionSize
        var dylibCmdSizes: [Int] = []
        for dylib in dylibs {
            let size = 24 + dylib.utf8.count + 1
            dylibCmdSizes.append((size + 7) / 8 * 8)
        }
        let encryptionCmdSize = is64Bit ? 24 : 20
        var commandSizes = [segmentCmdSize, 24] + dylibCmdSizes + [encryptionCmdSize]
        if codeSignature != nil { commandSizes.append(16) }
        let sizeofcmds = commandSizes.reduce(0, +)
        let ncmds = commandSizes.count
        let dataStart = headerSize + sizeofcmds

        let textOffset = dataStart
        let cstringOffset = textOffset + textBytes.count
        let methnameOffset = cstringOffset + cstringBytes.count
        let symoff = methnameOffset + methnameBytes.count
        let entrySize = is64Bit ? 16 : 12
        let stroff = symoff + symbols.count * entrySize
        let codesignOffset = stroff + strtab.count
        let segmentFilesize = textBytes.count + cstringBytes.count + methnameBytes.count

        var commands = Data()
        // LC_SEGMENT(_64) __TEXT
        commands.append(u32le(is64Bit ? 0x19 : 0x1))
        commands.append(u32le(UInt32(segmentCmdSize)))
        commands.append(fixedString("__TEXT", length: 16))
        if is64Bit {
            commands.append(u64le(0x1000_0000_0000))
            commands.append(u64le(UInt64(segmentFilesize)))
            commands.append(u64le(UInt64(dataStart)))
            commands.append(u64le(UInt64(segmentFilesize)))
        } else {
            commands.append(u32le(0x1000))
            commands.append(u32le(UInt32(segmentFilesize)))
            commands.append(u32le(UInt32(dataStart)))
            commands.append(u32le(UInt32(segmentFilesize)))
        }
        commands.append(u32le(7))
        commands.append(u32le(7))
        commands.append(u32le(UInt32(sectionCount)))
        commands.append(u32le(0))
        func section(sectname: String, address: UInt64, size: Int, offset: Int) {
            commands.append(fixedString(sectname, length: 16))
            commands.append(fixedString("__TEXT", length: 16))
            if is64Bit {
                commands.append(u64le(address))
                commands.append(u64le(UInt64(size)))
                commands.append(u32le(UInt32(offset)))
                commands.append(u32le(2))
                commands.append(u32le(0))
                commands.append(u32le(0))
                commands.append(u32le(0))
                commands.append(u32le(0))
                commands.append(u32le(0))
                commands.append(u32le(0))
            } else {
                commands.append(u32le(UInt32(address)))
                commands.append(u32le(UInt32(size)))
                commands.append(u32le(UInt32(offset)))
                commands.append(u32le(2))
                commands.append(u32le(0))
                commands.append(u32le(0))
                commands.append(u32le(0))
                commands.append(u32le(0))
                commands.append(u32le(0))
            }
        }
        section(sectname: "__text", address: 0x1000_0000_0000, size: textBytes.count, offset: textOffset)
        section(sectname: "__cstring", address: 0x1000_0000_0000 + UInt64(textBytes.count), size: cstringBytes.count, offset: cstringOffset)
        section(sectname: "__objc_methname", address: 0x1000_0000_0000 + UInt64(textBytes.count + cstringBytes.count), size: methnameBytes.count, offset: methnameOffset)
        // LC_SYMTAB
        commands.append(u32le(0x2))
        commands.append(u32le(24))
        commands.append(u32le(UInt32(symoff)))
        commands.append(u32le(UInt32(symbols.count)))
        commands.append(u32le(UInt32(stroff)))
        commands.append(u32le(UInt32(strtab.count)))
        // LC_LOAD_DYLIB
        for (index, dylib) in dylibs.enumerated() {
            commands.append(u32le(0xC))
            commands.append(u32le(UInt32(dylibCmdSizes[index])))
            commands.append(u32le(24))
            commands.append(u32le(0))
            commands.append(u32le(0))
            commands.append(u32le(0))
            var name = Data(dylib.utf8)
            name.append(0)
            name.append(Data(count: dylibCmdSizes[index] - 24 - name.count))
            commands.append(name)
        }
        // LC_ENCRYPTION_INFO(_64)
        commands.append(u32le(is64Bit ? 0x2C : 0x21))
        commands.append(u32le(UInt32(encryptionCmdSize)))
        commands.append(u32le(UInt32(dataStart)))
        commands.append(u32le(UInt32(textBytes.count)))
        commands.append(u32le(cryptid))
        if is64Bit { commands.append(u32le(0)) }
        // LC_CODE_SIGNATURE
        if let codeSignature {
            commands.append(u32le(0x1D))
            commands.append(u32le(16))
            commands.append(u32le(UInt32(codesignOffset)))
            commands.append(u32le(UInt32(codeSignature.count)))
        }

        var out = Data()
        out.append(u32le(is64Bit ? 0xfeed_facf : 0xfeed_face))
        out.append(u32le(cputype))
        out.append(u32le(cpuSubtype))
        out.append(u32le(2))
        out.append(u32le(UInt32(ncmds)))
        out.append(u32le(UInt32(sizeofcmds)))
        out.append(u32le(0))
        if is64Bit { out.append(u32le(0)) }
        out.append(commands)
        out.append(textBytes)
        out.append(cstringBytes)
        out.append(methnameBytes)
        for (index, _) in symbols.enumerated() {
            out.append(u32le(UInt32(strOffsets[index])))
            out.append(0x0F)
            out.append(1)
            out.append(u16le(0))
            if is64Bit {
                out.append(u64le(0))
            } else {
                out.append(u32le(0))
            }
        }
        out.append(strtab)
        if let codeSignature { out.append(codeSignature) }
        return out
    }

    private func makeFat(slices: [(cputype: UInt32, data: Data)]) -> Data {
        var out = Data()
        out.append(u32be(0xcafe_babe))
        out.append(u32be(UInt32(slices.count)))
        var offset = 8 + slices.count * 20
        for slice in slices {
            out.append(u32be(slice.cputype))
            out.append(u32be(0))
            out.append(u32be(UInt32(offset)))
            out.append(u32be(UInt32(slice.data.count)))
            out.append(u32be(0))
            offset += slice.data.count
        }
        for slice in slices { out.append(slice.data) }
        return out
    }

    // MARK: - CSBlob fixture builder

    private func derLength(_ count: Int) -> Data {
        if count < 128 { return Data([UInt8(count)]) }
        return Data([0x81, UInt8(count)])
    }

    private func derTLV(tag: UInt8, content: Data) -> Data {
        var data = Data([tag])
        data.append(derLength(content.count))
        data.append(content)
        return data
    }

    private func derOIDBytes(_ oid: String) -> Data {
        let arcs = oid.split(separator: ".").compactMap { Int($0) }
        var out = Data([UInt8(arcs[0] * 40 + arcs[1])])
        for arc in arcs.dropFirst(2) {
            var bytes: [UInt8] = []
            var value = arc
            bytes.append(UInt8(value & 0x7F))
            value >>= 7
            while value > 0 {
                bytes.append(UInt8(value & 0x7F) | 0x80)
                value >>= 7
            }
            out.append(contentsOf: bytes.reversed())
        }
        return out
    }

    /// DER entitlements fixture: SEQUENCE { SET { SEQUENCE {
    /// OID 1.2.3.4, SET { UTF8String "group.com.test" } } } }.
    private func makeDEREntitlements() -> Data {
        let oid = derTLV(tag: 0x06, content: derOIDBytes("1.2.3.4"))
        let values = derTLV(tag: 0x31, content: derTLV(tag: 0x0C, content: Data("group.com.test".utf8)))
        let entry = derTLV(tag: 0x30, content: oid + values)
        return derTLV(tag: 0x30, content: derTLV(tag: 0x31, content: entry))
    }

    private func makeCSBlob(
        xml: [String: Any]?, der: Data?, adHoc: Bool, cms: Bool, ident: String
    ) -> Data {
        var blobs: [(type: UInt32, data: Data)] = []
        var codeDirectory = Data()
        let identBytes = Data(ident.utf8) + Data([0])
        codeDirectory.append(u32be(0xfade_0c02))
        codeDirectory.append(u32be(UInt32(36 + identBytes.count)))
        codeDirectory.append(u32be(0x0002_0100))
        codeDirectory.append(u32be(adHoc ? 2 : 0))
        codeDirectory.append(u32be(0))
        codeDirectory.append(u32be(36))
        codeDirectory.append(u32be(0))
        codeDirectory.append(u32be(0))
        codeDirectory.append(u32be(0))
        codeDirectory.append(identBytes)
        blobs.append((0, codeDirectory))
        if let xml {
            let plist = try! PropertyListSerialization.data(fromPropertyList: xml, format: .xml, options: 0)
            var blob = Data()
            blob.append(u32be(0xfade_7171))
            blob.append(u32be(UInt32(8 + plist.count)))
            blob.append(plist)
            blobs.append((5, blob))
        }
        if let der {
            var blob = Data()
            blob.append(u32be(0xfade_7172))
            blob.append(u32be(UInt32(8 + der.count)))
            blob.append(der)
            blobs.append((7, blob))
        }
        if cms {
            var blob = Data()
            blob.append(u32be(0xfade_0b01))
            blob.append(u32be(8))
            blobs.append((0x10000, blob))
        }
        var out = Data()
        let totalLength = 12 + blobs.count * 8 + blobs.reduce(0) { $0 + $1.data.count }
        out.append(u32be(0xfade_0cc0))
        out.append(u32be(UInt32(totalLength)))
        out.append(u32be(UInt32(blobs.count)))
        var offset = 12 + blobs.count * 8
        for blob in blobs {
            out.append(u32be(blob.type))
            out.append(u32be(UInt32(offset)))
            offset += blob.data.count
        }
        for blob in blobs { out.append(blob.data) }
        return out
    }

    // MARK: - Stored-ZIP fixture builder

    private func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
        }
        return crc ^ 0xFFFF_FFFF
    }

    private struct ZipEntrySpec {
        let path: String
        let data: Data
        let isSymlink: Bool
        let declaredUncompressedSize: UInt32?
        init(path: String, data: Data, isSymlink: Bool = false, declaredUncompressedSize: UInt32? = nil) {
            self.path = path
            self.data = data
            self.isSymlink = isSymlink
            self.declaredUncompressedSize = declaredUncompressedSize
        }
    }

    /// A stored (method 0) ZIP: no compression, so the declared
    /// sizes are exactly the payload sizes.
    private func makeZIP(entries: [ZipEntrySpec]) -> Data {
        var out = Data()
        var central = Data()
        for spec in entries {
            let name = Data(spec.path.utf8)
            let crc = crc32(spec.data)
            let uncompressed = spec.declaredUncompressedSize ?? UInt32(spec.data.count)
            let localOffset = out.count
            out.append(u32le(0x0403_4b50))
            out.append(u16le(20))
            out.append(u16le(0))
            out.append(u16le(0))
            out.append(u16le(0))
            out.append(u16le(0))
            out.append(u32le(crc))
            out.append(u32le(UInt32(spec.data.count)))
            out.append(u32le(uncompressed))
            out.append(u16le(UInt16(name.count)))
            out.append(u16le(0))
            out.append(name)
            out.append(spec.data)
            central.append(u32le(0x0201_4b50))
            central.append(u16le(spec.isSymlink ? 0x0314 : 20))
            central.append(u16le(20))
            central.append(u16le(0))
            central.append(u16le(0))
            central.append(u16le(0))
            central.append(u16le(0))
            central.append(u32le(crc))
            central.append(u32le(UInt32(spec.data.count)))
            central.append(u32le(uncompressed))
            central.append(u16le(UInt16(name.count)))
            central.append(u16le(0))
            central.append(u16le(0))
            central.append(u16le(0))
            central.append(u16le(0))
            central.append(u32le(spec.isSymlink ? (UInt32(0o120777) << 16) : 0))
            central.append(u32le(UInt32(localOffset)))
            central.append(name)
        }
        let cdOffset = out.count
        out.append(central)
        out.append(u32le(0x0605_4b50))
        out.append(u16le(0))
        out.append(u16le(0))
        out.append(u16le(UInt16(entries.count)))
        out.append(u16le(UInt16(entries.count)))
        out.append(u32le(UInt32(central.count)))
        out.append(u32le(UInt32(cdOffset)))
        out.append(u16le(0))
        return out
    }

    private func infoPlist(bundleID: String, executable: String) -> Data {
        let dict: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleExecutable": executable,
            "CFBundleName": "TestApp",
            "CFBundleShortVersionString": "1.0",
        ]
        return try! PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }

    private func writeIPA(
        in directory: URL, name: String, entries: [ZipEntrySpec]
    ) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try makeZIP(entries: entries).write(to: url, options: .atomic)
        return url
    }

    // MARK: - Mach-O parser

    func testThin64BitMachOParsesDylibsSymbolsStringsAndSvc() throws {
        let data = makeMachO(
            symbols: ["_container_query_create", "_normal_symbol"],
            dylibs: ["/usr/lib/libsystem_containermanager.dylib"],
            cstrings: ["com.apple.containermanagerd", "hello"],
            selectors: ["doThing:"],
            includeSvc: true)
        let reports = try IPAAuditMachOParser.parse(data)
        XCTAssertEqual(reports.count, 1)
        let report = reports[0]
        XCTAssertEqual(report.architecture, "arm64")
        XCTAssertTrue(report.is64Bit)
        XCTAssertFalse(report.isFat)
        XCTAssertEqual(report.linkedDylibs, ["/usr/lib/libsystem_containermanager.dylib"])
        XCTAssertTrue(report.symbols.contains("_container_query_create"))
        XCTAssertTrue(report.cstrings.contains("com.apple.containermanagerd"))
        XCTAssertTrue(report.objcSelectors.contains("doThing:"))
        XCTAssertTrue(report.hasDirectSyscall)
        XCTAssertEqual(report.directSyscallCount, 1)
        XCTAssertFalse(report.isFairPlayEncrypted)
    }

    func testArm64eSubtypeIsNamed() throws {
        let data = makeMachO(cpuSubtype: 2)
        let reports = try IPAAuditMachOParser.parse(data)
        XCTAssertEqual(reports[0].architecture, "arm64e")
    }

    func test32BitMachOParses() throws {
        let data = makeMachO(
            symbols: ["_fsgetpath"],
            dylibs: ["/usr/lib/libSystem.dylib"],
            cstrings: ["plain"],
            is64Bit: false)
        let reports = try IPAAuditMachOParser.parse(data)
        XCTAssertEqual(reports.count, 1)
        XCTAssertFalse(reports[0].is64Bit)
        XCTAssertTrue(reports[0].symbols.contains("_fsgetpath"))
        XCTAssertEqual(reports[0].linkedDylibs, ["/usr/lib/libSystem.dylib"])
    }

    func testFatBinaryReturnsUnionOfSlices() throws {
        let arm = makeMachO(symbols: ["_container_query_create"])
        let x86 = makeMachO(symbols: ["_x86_only_symbol"], cputype: 0x0100_0007)
        let fat = makeFat(slices: [(0x0100_000C, arm), (0x0100_0007, x86)])
        let reports = try IPAAuditMachOParser.parse(fat)
        XCTAssertEqual(reports.count, 2)
        XCTAssertTrue(reports[0].isFat)
        XCTAssertEqual(reports[0].sliceCount, 2)
        XCTAssertEqual(reports[1].architecture, "x86_64")
        let allSymbols = reports.flatMap(\.symbols)
        XCTAssertTrue(allSymbols.contains("_container_query_create"))
        XCTAssertTrue(allSymbols.contains("_x86_only_symbol"))
    }

    func testFatSliceBombIsRejected() {
        var header = Data()
        header.append(u32be(0xcafe_babe))
        header.append(u32be(1_025))
        XCTAssertThrowsError(try IPAAuditMachOParser.parse(header))
    }

    func testTruncatedMachOThrows() {
        XCTAssertThrowsError(try IPAAuditMachOParser.parse(Data([0xCF, 0xFA, 0xED, 0xFE])))
        XCTAssertThrowsError(try IPAAuditMachOParser.parse(Data()))
        XCTAssertThrowsError(try IPAAuditMachOParser.parse(Data("not a mach-o at all, just text".utf8)))
    }

    func testFairPlayCryptidIsReported() throws {
        let data = makeMachO(cryptid: 1)
        let reports = try IPAAuditMachOParser.parse(data)
        XCTAssertTrue(reports[0].isFairPlayEncrypted)
        let plain = makeMachO(cryptid: 0)
        XCTAssertFalse(try IPAAuditMachOParser.parse(plain)[0].isFairPlayEncrypted)
    }

    func testX86SliceDoesNotReportARMOnlySvc() throws {
        let data = makeMachO(includeSvc: true, cputype: 0x0100_0007)
        let reports = try IPAAuditMachOParser.parse(data)
        XCTAssertFalse(reports[0].hasDirectSyscall)
        XCTAssertEqual(reports[0].directSyscallCount, 0)
    }

    func testCodeSignaturePayloadIsHandedThrough() throws {
        let blob = makeCSBlob(xml: ["get-task-allow": true], der: nil, adHoc: false, cms: false, ident: "com.test.app")
        let data = makeMachO(codeSignature: blob)
        let reports = try IPAAuditMachOParser.parse(data)
        XCTAssertEqual(reports[0].codeSignature, blob)
    }

    // MARK: - CSBlob parser

    func testCSBlobParsesXMLAndDERAndMergesAppGroups() throws {
        let xml: [String: Any] = [
            "com.apple.security.application-groups": ["group.a"],
            "get-task-allow": true,
        ]
        let blob = makeCSBlob(xml: xml, der: makeDEREntitlements(), adHoc: true, cms: true, ident: "com.test.app")
        let parsed = try IPAAuditCSBlobParser.parse(blob)
        XCTAssertTrue(parsed.hasXMLEntitlements)
        XCTAssertTrue(parsed.hasDEREntitlements)
        XCTAssertTrue(parsed.isAdHoc)
        XCTAssertTrue(parsed.hasCMSSignature)
        XCTAssertEqual(parsed.codeDirectoryIdent, "com.test.app")
        XCTAssertTrue(parsed.appGroups.contains("group.a"))
        // The DER fixture contributes OID key 1.2.3.4.
        XCTAssertTrue(parsed.mergedEntitlements.contains(where: { $0.key == "1.2.3.4" }))
        XCTAssertTrue(parsed.mergedEntitlements.contains(where: { $0.key == "get-task-allow" && $0.value == "true" }))
    }

    func testCSBlobWithoutEntitlementsReportsNone() throws {
        let blob = makeCSBlob(xml: nil, der: nil, adHoc: false, cms: false, ident: "com.test.app")
        let parsed = try IPAAuditCSBlobParser.parse(blob)
        XCTAssertTrue(parsed.hasNoEntitlements)
        XCTAssertFalse(parsed.isAdHoc)
        XCTAssertFalse(parsed.hasCMSSignature)
        XCTAssertTrue(parsed.mergedEntitlements.isEmpty)
    }

    func testCSBlobBadMagicThrows() {
        var bad = Data(count: 64)
        bad[0] = 0xDE
        bad[1] = 0xAD
        XCTAssertThrowsError(try IPAAuditCSBlobParser.parse(bad))
        XCTAssertThrowsError(try IPAAuditCSBlobParser.parse(Data()))
    }

    func testCSBlobMalformedXMLThrows() throws {
        var xml = Data()
        xml.append(u32be(0xfade_7171))
        let payload = Data("this is not a plist".utf8)
        xml.append(u32be(UInt32(8 + payload.count)))
        xml.append(payload)
        var blob = Data()
        blob.append(u32be(0xfade_0cc0))
        blob.append(u32be(UInt32(12 + 8 + xml.count)))
        blob.append(u32be(1))
        blob.append(u32be(5))
        blob.append(u32be(UInt32(12 + 8)))
        blob.append(xml)
        XCTAssertThrowsError(try IPAAuditCSBlobParser.parse(blob))
    }

    func testDERDecoderHandlesOIDAndStrings() throws {
        let der = makeDEREntitlements()
        let dict = try IPAAuditCSBlobParser.parseDEREntitlements(der)
        XCTAssertEqual(dict["1.2.3.4"] as? [String], ["group.com.test"])
        XCTAssertEqual(IPAAuditCSBlobParser.decodeOID(Data([0x2A, 0x03, 0x04])), "1.2.3.4")
    }

    func testDEREmptyDataReturnsEmptyDictionary() throws {
        XCTAssertTrue(try IPAAuditCSBlobParser.parseDEREntitlements(Data()).isEmpty)
    }

    func testEntitlementMergeIsAntiShadowing() {
        let base: [String: Any] = [
            "key.bool": false,
            "key.groups": ["a"],
            "com.apple.private.security.container-required": true,
            "key.scalar": "xml-value",
        ]
        let incoming: [String: Any] = [
            "key.bool": true,
            "key.groups": ["b"],
            "com.apple.private.security.container-required": false,
            "key.scalar": "der-value",
        ]
        let merged = IPAAuditCSBlobParser.mergeEntitlementDictionaries(base, incoming)
        XCTAssertEqual(merged["key.bool"] as? Bool, true)
        XCTAssertEqual(merged["key.groups"] as? [String], ["a", "b"])
        XCTAssertEqual(merged["com.apple.private.security.container-required"] as? Bool, false)
        XCTAssertEqual(merged["key.scalar"] as? String, "der-value")
    }

    // MARK: - Threat catalog + verdict

    func testSymbolRulesMatchAndVerdictIsHighRisk() {
        let findings = IPAAuditThreatCatalog.match(
            dylibs: ["/usr/lib/libsystem_containermanager.dylib"],
            symbols: ["_container_query_create", "_fsgetpath"],
            strings: [],
            entitlements: [])
        XCTAssertTrue(findings.contains(where: { $0.ruleID == "DYLIB_CONTAINERMANAGER" }))
        XCTAssertTrue(findings.contains(where: { $0.ruleID == "SYM_QUERY_CREATE" }))
        XCTAssertTrue(findings.contains(where: { $0.ruleID == "SYM_FSGETPATH" }))
        XCTAssertTrue(findings.allSatisfy { $0.severity == .highRisk })
        XCTAssertEqual(IPAAuditThreatCatalog.verdict(findings: findings, bundleID: nil), .highRisk)
    }

    func testWhitelistNeverSuppressesHighRisk() {
        let findings = IPAAuditThreatCatalog.match(
            dylibs: [], symbols: ["_container_query_create"], strings: [], entitlements: [])
        XCTAssertEqual(
            IPAAuditThreatCatalog.verdict(findings: findings, bundleID: "com.huami.gestultx"),
            .highRisk)
    }

    func testCleanWhitelistedBundleIsKnownTool() {
        XCTAssertEqual(
            IPAAuditThreatCatalog.verdict(findings: [], bundleID: "com.huami.gestultx"),
            .knownTool)
        XCTAssertEqual(
            IPAAuditThreatCatalog.verdict(findings: [], bundleID: "com.huami.gestultx.ShareExtension"),
            .knownTool)
    }

    func testCautionFindingYieldsCautionVerdict() {
        let findings = IPAAuditThreatCatalog.match(
            dylibs: [], symbols: [], strings: ["audiomxd"], entitlements: [])
        XCTAssertTrue(findings.contains(where: { $0.ruleID == "AUDIOMXD_BYPASS" }))
        XCTAssertEqual(IPAAuditThreatCatalog.verdict(findings: findings, bundleID: "com.test.clean"), .caution)
    }

    func testCleanUnknownBundleIsSafe() {
        XCTAssertEqual(IPAAuditThreatCatalog.verdict(findings: [], bundleID: "com.test.clean"), .safe)
    }

    func testWQGuardBundleIDIsNotWhitelisted() {
        XCTAssertFalse(IPAAuditThreatCatalog.trustedBundleIDs.contains("com.wqguard.app"))
        XCTAssertEqual(
            IPAAuditThreatCatalog.verdict(findings: [], bundleID: "com.wqguard.app"),
            .safe)
    }

    func testGetTaskAllowEntitlementOnlyMatchesWhenTrue() {
        let enabled = IPAAuditThreatCatalog.match(
            dylibs: [], symbols: [], strings: [],
            entitlements: [IPAAuditEntitlement(key: "get-task-allow", value: "true", source: "XML")])
        XCTAssertTrue(enabled.contains(where: { $0.ruleID == "ENT_GET_TASK_ALLOW" }))
        let disabled = IPAAuditThreatCatalog.match(
            dylibs: [], symbols: [], strings: [],
            entitlements: [IPAAuditEntitlement(key: "get-task-allow", value: "false", source: "XML")])
        XCTAssertFalse(disabled.contains(where: { $0.ruleID == "ENT_GET_TASK_ALLOW" }))
    }

    func testHookFrameworkDylibIsHighRisk() {
        let findings = IPAAuditThreatCatalog.match(
            dylibs: ["/usr/lib/libhooker.dylib"], symbols: [], strings: [], entitlements: [])
        XCTAssertTrue(findings.contains(where: { $0.ruleID == "INJECTED_HOOK_FRAMEWORK_LIBHOOKER" }))
    }

    // MARK: - CVE radar

    func testCVERadarHasThirteenEntries() {
        XCTAssertEqual(IPAAuditCVERadar.entries.count, 13)
    }

    func testCVERadarStoresNVDVerifiedScoresNotUpstreamClaims() {
        let byID = Dictionary(uniqueKeysWithValues: IPAAuditCVERadar.entries.map { ($0.id, $0) })
        XCTAssertEqual(byID["CVE-2026-112676"]?.verifiedCVSS, 7.5)
        XCTAssertEqual(byID["CVE-2026-112676"]?.verification, .verified)
        // Upstream claimed 9.2; NVD says 9.8.
        XCTAssertEqual(byID["CVE-2026-111497"]?.verifiedCVSS, 9.8)
        XCTAssertEqual(byID["CVE-2026-111497"]?.upstreamClaimedCVSS, 9.2)
        // Upstream claimed 8.8; NVD says 6.1.
        XCTAssertEqual(byID["CVE-2026-112611"]?.verifiedCVSS, 6.1)
        // Upstream claimed 8.8; NVD says 10.0.
        XCTAssertEqual(byID["CVE-2026-113897"]?.verifiedCVSS, 10.0)
        // The two entries with no CVE number carry no score.
        XCTAssertNil(byID["0day:worse_query"]?.verifiedCVSS)
        XCTAssertEqual(byID["0day:worse_query"]?.verification, .unverified)
        XCTAssertNil(byID["PoC:BookRestore"]?.verifiedCVSS)
        XCTAssertEqual(byID["PoC:BookRestore"]?.verification, .unverified)
    }

    func testCVERangeEntryListsUnverifiedIDs() {
        let entry = IPAAuditCVERadar.entries.first(where: { $0.id == "CVE-2026-113964–70" })
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.unverifiedIDs, ["CVE-2026-113966", "CVE-2026-113967"])
        XCTAssertEqual(entry?.verifiedCVSSByID["CVE-2026-113970"], 8.8)
        XCTAssertEqual(entry?.verifiedCVSSByID["CVE-2026-113964"], 5.4)
        XCTAssertNil(entry?.verifiedCVSS)
    }

    func testCVEExposureUsesVerifiedFixedVersions() {
        let byID = Dictionary(uniqueKeysWithValues: IPAAuditCVERadar.entries.map { ($0.id, $0) })
        let photos = byID["CVE-2026-112676"]!
        XCTAssertEqual(
            IPAAuditCVERadar.exposure(of: photos, for: IPAAuditOSVersion(major: 27, minor: 0, patch: 1)),
            .exposed)
        XCTAssertEqual(
            IPAAuditCVERadar.exposure(of: photos, for: IPAAuditOSVersion(major: 27, minor: 2, patch: 0)),
            .patched)
        XCTAssertEqual(
            IPAAuditCVERadar.exposure(of: photos, for: IPAAuditOSVersion(major: 26, minor: 7, patch: 1)),
            .exposed)
        XCTAssertEqual(
            IPAAuditCVERadar.exposure(of: photos, for: IPAAuditOSVersion(major: 26, minor: 7, patch: 2)),
            .patched)
    }

    func testCVEExposureIsUnknownWithoutVerifiedBranchFix() {
        let byID = Dictionary(uniqueKeysWithValues: IPAAuditCVERadar.entries.map { ($0.id, $0) })
        // Brotli: no iOS fixed version is named in the NVD record.
        XCTAssertEqual(
            IPAAuditCVERadar.exposure(of: byID["CVE-2026-111497"]!, for: IPAAuditOSVersion(major: 27, minor: 0, patch: 1)),
            .unknown)
        // 113897: only an iOS 27.2 fix is verified; the 26 branch is unknown.
        XCTAssertEqual(
            IPAAuditCVERadar.exposure(of: byID["CVE-2026-113897"]!, for: IPAAuditOSVersion(major: 26, minor: 7, patch: 2)),
            .unknown)
        XCTAssertEqual(
            IPAAuditCVERadar.exposure(of: byID["CVE-2026-113897"]!, for: IPAAuditOSVersion(major: 27, minor: 2, patch: 0)),
            .patched)
    }

    func testWorseQueryExposureFollows273Beta2Sentinel() {
        let entry = IPAAuditCVERadar.entries.first(where: { $0.id == "0day:worse_query" })!
        XCTAssertEqual(
            IPAAuditCVERadar.exposure(of: entry, for: IPAAuditOSVersion(major: 27, minor: 2, patch: 1)),
            .exposed)
        XCTAssertEqual(
            IPAAuditCVERadar.exposure(of: entry, for: IPAAuditOSVersion(major: 27, minor: 3, patch: 0, beta: 1)),
            .exposed)
        XCTAssertEqual(
            IPAAuditCVERadar.exposure(of: entry, for: IPAAuditOSVersion(major: 27, minor: 3, patch: 0, beta: 2)),
            .patched)
        XCTAssertEqual(
            IPAAuditCVERadar.exposure(of: entry, for: IPAAuditOSVersion(major: 27, minor: 3, patch: 0)),
            .patched)
    }

    func testOSVersionParsing() {
        XCTAssertEqual(IPAAuditOSVersion(string: "27.0.1"), IPAAuditOSVersion(major: 27, minor: 0, patch: 1))
        XCTAssertEqual(IPAAuditOSVersion(string: "27.3 beta 2"), IPAAuditOSVersion(major: 27, minor: 3, patch: 0, beta: 2))
        XCTAssertEqual(IPAAuditOSVersion(string: "iOS 27.2"), IPAAuditOSVersion(major: 27, minor: 2, patch: 0))
        XCTAssertNil(IPAAuditOSVersion(string: ""))
        XCTAssertNil(IPAAuditOSVersion(string: "not a version"))
    }

    // MARK: - IPA scanner (end to end over fixture IPAs)

    func testEvilIPAIsHighRiskWithRealFindings() throws {
        let directory = try tempDirectory()
        let main = makeMachO(
            symbols: ["_container_query_create"],
            dylibs: ["/usr/lib/libsystem_containermanager.dylib"],
            cstrings: ["com.apple.containermanagerd"])
        let framework = makeMachO(dylibs: ["/usr/lib/libhooker.dylib"])
        let ipa = try writeIPA(in: directory, name: "evil.ipa", entries: [
            ZipEntrySpec(path: "Payload/TestApp.app/TestApp", data: main),
            ZipEntrySpec(path: "Payload/TestApp.app/Info.plist", data: infoPlist(bundleID: "com.test.evil", executable: "TestApp")),
            ZipEntrySpec(path: "Payload/TestApp.app/Frameworks/Evil.framework/Evil", data: framework),
            ZipEntrySpec(path: "Payload/TestApp.app/Assets.txt", data: Data("hello".utf8)),
        ])
        let report = try IPAAuditScanner.audit(
            ipaURL: ipa, deviceOSVersion: IPAAuditOSVersion(major: 27, minor: 0, patch: 1))
        XCTAssertEqual(report.bundleID, "com.test.evil")
        XCTAssertEqual(report.verdict, .highRisk)
        XCTAssertTrue(report.findings.contains(where: { $0.ruleID == "DYLIB_CONTAINERMANAGER" }))
        XCTAssertTrue(report.findings.contains(where: { $0.ruleID == "SYM_QUERY_CREATE" }))
        XCTAssertTrue(report.findings.contains(where: { $0.ruleID == "INJECTED_HOOK_FRAMEWORK_LIBHOOKER" }))
        XCTAssertEqual(report.binaries.count, 2)
        XCTAssertFalse(report.fileSHA256.isEmpty)
        let cveRow = report.cveExposure.first(where: { $0.entryID == "CVE-2026-112676" })
        XCTAssertEqual(cveRow?.exposure, .exposed)
        XCTAssertEqual(cveRow?.verifiedCVSS, 7.5)
    }

    func testCleanIPAISafe() throws {
        let directory = try tempDirectory()
        let main = makeMachO(symbols: ["_normal_symbol"], cstrings: ["hello"])
        let ipa = try writeIPA(in: directory, name: "clean.ipa", entries: [
            ZipEntrySpec(path: "Payload/TestApp.app/TestApp", data: main),
            ZipEntrySpec(path: "Payload/TestApp.app/Info.plist", data: infoPlist(bundleID: "com.test.clean", executable: "TestApp")),
        ])
        let report = try IPAAuditScanner.audit(
            ipaURL: ipa, deviceOSVersion: IPAAuditOSVersion(major: 27, minor: 2, patch: 0))
        XCTAssertEqual(report.verdict, .safe)
        XCTAssertTrue(report.findings.isEmpty)
        XCTAssertEqual(report.cveExposure.first(where: { $0.entryID == "CVE-2026-112676" })?.exposure, .patched)
    }

    func testLilaShiftOwnIPAIsKnownTool() throws {
        let directory = try tempDirectory()
        let main = makeMachO(symbols: ["_normal_symbol"])
        let ipa = try writeIPA(in: directory, name: "self.ipa", entries: [
            ZipEntrySpec(path: "Payload/TestApp.app/TestApp", data: main),
            ZipEntrySpec(path: "Payload/TestApp.app/Info.plist", data: infoPlist(bundleID: "com.huami.gestultx", executable: "TestApp")),
        ])
        let report = try IPAAuditScanner.audit(
            ipaURL: ipa, deviceOSVersion: IPAAuditOSVersion(major: 27, minor: 0, patch: 1))
        XCTAssertEqual(report.verdict, .knownTool)
    }

    func testFairPlayBinaryIsSkippedNotCleared() throws {
        let directory = try tempDirectory()
        let main = makeMachO(symbols: ["_container_query_create"], cryptid: 1)
        let ipa = try writeIPA(in: directory, name: "encrypted.ipa", entries: [
            ZipEntrySpec(path: "Payload/TestApp.app/TestApp", data: main),
            ZipEntrySpec(path: "Payload/TestApp.app/Info.plist", data: infoPlist(bundleID: "com.test.encrypted", executable: "TestApp")),
        ])
        let report = try IPAAuditScanner.audit(
            ipaURL: ipa, deviceOSVersion: IPAAuditOSVersion(major: 27, minor: 0, patch: 1))
        XCTAssertEqual(report.binaries.count, 1)
        XCTAssertTrue(report.binaries[0].wasSkipped)
        XCTAssertTrue(report.binaries[0].isFairPlayEncrypted)
        XCTAssertTrue(report.findings.contains(where: { $0.ruleID == "FAIRPLAY_ENCRYPTED_SKIPPED" }))
        XCTAssertFalse(report.findings.contains(where: { $0.ruleID == "SYM_QUERY_CREATE" }))
        XCTAssertEqual(report.verdict, .caution)
        XCTAssertEqual(report.skippedFairPlayCount, 1)
    }

    func testZipSlipEntryIsRejected() throws {
        let directory = try tempDirectory()
        let main = makeMachO()
        let ipa = try writeIPA(in: directory, name: "slip.ipa", entries: [
            ZipEntrySpec(path: "Payload/TestApp.app/TestApp", data: main),
            ZipEntrySpec(path: "Payload/TestApp.app/Info.plist", data: infoPlist(bundleID: "com.test.slip", executable: "TestApp")),
            ZipEntrySpec(path: "../Escape.txt", data: Data("evil".utf8)),
        ])
        XCTAssertThrowsError(try IPAAuditScanner.audit(
            ipaURL: ipa, deviceOSVersion: IPAAuditOSVersion(major: 27, minor: 0, patch: 1)))
    }

    func testAbsoluteEntryPathIsRejected() {
        XCTAssertThrowsError(try IPAAuditScanner.safeRelativePath("/etc/passwd"))
        XCTAssertThrowsError(try IPAAuditScanner.safeRelativePath("Payload//Double.txt"))
        XCTAssertEqual(try IPAAuditScanner.safeRelativePath("Payload/TestApp.app/TestApp"), "Payload/TestApp.app/TestApp")
    }

    func testDecompressionBombDeclarationIsRejected() throws {
        let directory = try tempDirectory()
        let main = makeMachO()
        let ipa = try writeIPA(in: directory, name: "bomb.ipa", entries: [
            ZipEntrySpec(path: "Payload/TestApp.app/TestApp", data: main),
            ZipEntrySpec(path: "Payload/TestApp.app/Info.plist", data: infoPlist(bundleID: "com.test.bomb", executable: "TestApp")),
            ZipEntrySpec(path: "Payload/TestApp.app/Big.bin", data: Data(count: 16), declaredUncompressedSize: 300_000_000),
        ])
        XCTAssertThrowsError(try IPAAuditScanner.audit(
            ipaURL: ipa, deviceOSVersion: IPAAuditOSVersion(major: 27, minor: 0, patch: 1)))
    }

    func testEscapingSymlinkIsFlaggedAndStripped() throws {
        let directory = try tempDirectory()
        let main = makeMachO()
        let ipa = try writeIPA(in: directory, name: "link.ipa", entries: [
            ZipEntrySpec(path: "Payload/TestApp.app/TestApp", data: main),
            ZipEntrySpec(path: "Payload/TestApp.app/Info.plist", data: infoPlist(bundleID: "com.test.link", executable: "TestApp")),
            ZipEntrySpec(path: "Payload/TestApp.app/Frameworks/Link", data: Data("/etc/passwd".utf8), isSymlink: true),
        ])
        let report = try IPAAuditScanner.audit(
            ipaURL: ipa, deviceOSVersion: IPAAuditOSVersion(major: 27, minor: 0, patch: 1))
        XCTAssertTrue(report.findings.contains(where: { $0.ruleID == "ESCAPING_SYMLINK" }))
        XCTAssertEqual(report.verdict, .highRisk)
        XCTAssertEqual(report.strippedSymlinkCount, 1)
    }

    func testIPAMissingAppBundleThrows() throws {
        let directory = try tempDirectory()
        let ipa = try writeIPA(in: directory, name: "empty.ipa", entries: [
            ZipEntrySpec(path: "README.txt", data: Data("hello".utf8)),
        ])
        XCTAssertThrowsError(try IPAAuditScanner.audit(
            ipaURL: ipa, deviceOSVersion: IPAAuditOSVersion(major: 27, minor: 0, patch: 1)))
    }

    func testScanCancellationStopsTheScan() throws {
        let directory = try tempDirectory()
        let main = makeMachO()
        let ipa = try writeIPA(in: directory, name: "cancel.ipa", entries: [
            ZipEntrySpec(path: "Payload/TestApp.app/TestApp", data: main),
            ZipEntrySpec(path: "Payload/TestApp.app/Info.plist", data: infoPlist(bundleID: "com.test.cancel", executable: "TestApp")),
        ])
        XCTAssertThrowsError(try IPAAuditScanner.audit(
            ipaURL: ipa, deviceOSVersion: IPAAuditOSVersion(major: 27, minor: 0, patch: 1),
            isCancelled: { true }))
    }

    func testNilDeviceVersionMakesRadarUnknown() throws {
        let directory = try tempDirectory()
        let main = makeMachO()
        let ipa = try writeIPA(in: directory, name: "n version.ipa", entries: [
            ZipEntrySpec(path: "Payload/TestApp.app/TestApp", data: main),
            ZipEntrySpec(path: "Payload/TestApp.app/Info.plist", data: infoPlist(bundleID: "com.test.clean", executable: "TestApp")),
        ])
        let report = try IPAAuditScanner.audit(ipaURL: ipa, deviceOSVersion: nil)
        XCTAssertTrue(report.cveExposure.allSatisfy { $0.exposure == .unknown })
    }

    // MARK: - Report export

    func testReportJSONRoundTrip() throws {
        let directory = try tempDirectory()
        let main = makeMachO(symbols: ["_container_query_create"])
        let ipa = try writeIPA(in: directory, name: "roundtrip.ipa", entries: [
            ZipEntrySpec(path: "Payload/TestApp.app/TestApp", data: main),
            ZipEntrySpec(path: "Payload/TestApp.app/Info.plist", data: infoPlist(bundleID: "com.test.evil", executable: "TestApp")),
        ])
        let report = try IPAAuditScanner.audit(
            ipaURL: ipa, deviceOSVersion: IPAAuditOSVersion(major: 27, minor: 0, patch: 1))
        let data = try report.jsonData()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(IPAAuditReport.self, from: data)
        XCTAssertEqual(decoded, report)
        XCTAssertEqual(decoded.verdict, .highRisk)
    }

    func testReportMarkdownAndTextContainVerdictAndUnverified() throws {
        let directory = try tempDirectory()
        let main = makeMachO()
        let ipa = try writeIPA(in: directory, name: "export.ipa", entries: [
            ZipEntrySpec(path: "Payload/TestApp.app/TestApp", data: main),
            ZipEntrySpec(path: "Payload/TestApp.app/Info.plist", data: infoPlist(bundleID: "com.test.clean", executable: "TestApp")),
        ])
        let report = try IPAAuditScanner.audit(
            ipaURL: ipa, deviceOSVersion: IPAAuditOSVersion(major: 27, minor: 0, patch: 1))
        XCTAssertTrue(report.markdown().contains("com.test.clean"))
        XCTAssertTrue(report.markdown().contains("Unverified"))
        XCTAssertTrue(report.plainText().contains("Safe & Compliant"))
        XCTAssertTrue(report.plainText().contains("0day:worse_query"))
    }

    // MARK: - W3 registration

    func testW3RegistrationListsSixFeatures() {
        XCTAssertEqual(W3Registration.features.count, 6)
        let ids = W3Registration.features.map(\.id)
        XCTAssertEqual(Set(ids).count, 6)
        XCTAssertTrue(ids.contains("w3.macho"))
        XCTAssertTrue(ids.contains("w3.csblob"))
        XCTAssertTrue(ids.contains("w3.ipa-scan"))
        XCTAssertTrue(ids.contains("w3.threat-catalog"))
        XCTAssertTrue(ids.contains("w3.cve-radar"))
        XCTAssertTrue(ids.contains("w3.report-export"))
        XCTAssertTrue(W3Registration.features.allSatisfy { $0.viewKind == .ipaAudit })
        XCTAssertTrue(W3Registration.features.allSatisfy { $0.category == .deviceDiagnostics })
    }
}
