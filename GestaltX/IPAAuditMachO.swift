// SPDX-License-Identifier: GPL-3.0-only
// IPA Audit — Mach-O parser (W3, LilaShift 5.0.0).
//
// Static Mach-O parsing ported from the design of Kianuni/WQGuard
// v1.3.6 (`Sources/WQGuardCore/MachO/MachOParser.swift`, MIT,
// Copyright (c) 2026 WQGuard Contributors) — see W3NOTICES.md.
// This is a compact re-implementation for LilaShift, not a copy of
// the upstream file: it keeps the upstream invariants (fat-slice
// cap, 64-bit overflow-safe bounds checks, arm64/arm64e union,
// LC_SYMTAB / LC_LOAD_DYLIB / LC_ENCRYPTION_INFO_64 /
// LC_CODE_SIGNATURE traversal, ARM64 `svc #0x80` scan) and drops
// the parts LilaShift does not need (macOS CLI paths, live
// process inspection).
//
// Read-only: the parser never executes, maps or loads the binary;
// every read is bounds-checked against the supplied `Data`, and
// any out-of-range value is an error, never a clamped guess.
import Foundation

/// Errors raised by the IPA audit engine. The message is already
/// user-facing text (built with `L()` at the throw site where a
/// localized string exists); the view shows it verbatim.
struct IPAAuditError: LocalizedError, Equatable, Sendable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// MARK: - Bounds-checked binary reader

/// Little- and big-endian reads over an in-memory `Data` buffer.
/// Every accessor returns `nil` out of bounds instead of trapping,
/// so a malformed header can never crash the scanner.
struct IPAAuditDataReader: Sendable {
    let data: Data

    var count: Int { data.count }

    /// True when `offset ..< offset + size` lies inside the buffer.
    /// Written to avoid overflow: `offset + size` is never computed
    /// on unchecked values.
    func contains(offset: Int, size: Int) -> Bool {
        guard offset >= 0, size >= 0, offset <= data.count else { return false }
        return size <= data.count - offset
    }

    func uint8(at offset: Int) -> UInt8? {
        guard contains(offset: offset, size: 1) else { return nil }
        return data[offset]
    }

    func uint16LE(at offset: Int) -> UInt16? {
        guard contains(offset: offset, size: 2) else { return nil }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    func uint32LE(at offset: Int) -> UInt32? {
        guard contains(offset: offset, size: 4) else { return nil }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    func uint32BE(at offset: Int) -> UInt32? {
        guard contains(offset: offset, size: 4) else { return nil }
        return (UInt32(data[offset]) << 24)
            | (UInt32(data[offset + 1]) << 16)
            | (UInt32(data[offset + 2]) << 8)
            | UInt32(data[offset + 3])
    }

    func uint64LE(at offset: Int) -> UInt64? {
        guard contains(offset: offset, size: 8) else { return nil }
        var value: UInt64 = 0
        for index in 0..<8 {
            value |= UInt64(data[offset + index]) << (index * 8)
        }
        return value
    }

    func subdata(offset: Int, size: Int) -> Data? {
        guard contains(offset: offset, size: size) else { return nil }
        return data.subdata(in: offset..<(offset + size))
    }

    /// A NUL-terminated UTF-8 string starting at `offset`, or `nil`
    /// when no NUL appears within `maxLength` bytes or the bytes
    /// are not valid UTF-8. The returned string never includes the
    /// terminator.
    func cString(at offset: Int, maxLength: Int) -> String? {
        guard offset >= 0, offset < data.count, maxLength > 0 else { return nil }
        let limit = min(data.count - offset, maxLength)
        var end = offset
        while end < offset + limit, data[end] != 0 {
            end += 1
        }
        guard end < offset + limit else { return nil }
        guard end > offset else { return "" }
        return String(bytes: data[offset..<end], encoding: .utf8)
    }
}

// MARK: - Parsed Mach-O report

/// What the parser learned from one Mach-O image (one thin binary,
/// or one fat slice). Only matched evidence is kept in the audit
/// report; the full symbol/string tables stay in this struct so the
/// rule engine can match against them without re-parsing.
struct IPAAuditMachOReport: Equatable, Sendable {
    /// CPU type string, e.g. "arm64", "arm64e", "x86_64".
    let architecture: String
    let is64Bit: Bool
    /// True when the source file was a fat binary.
    let isFat: Bool
    /// Slice count of the source fat binary (1 for a thin binary).
    let sliceCount: Int
    /// Install names from LC_LOAD_DYLIB / LC_LOAD_WEAK_DYLIB /
    /// LC_REEXPORT_DYLIB, in load-command order, deduplicated.
    let linkedDylibs: [String]
    /// Imported + exported symbol names from LC_SYMTAB.
    let symbols: [String]
    /// True when the symbol table was cut off by `maxSymbols`.
    let symbolsTruncated: Bool
    /// NUL-terminated strings from __TEXT,__cstring.
    let cstrings: [String]
    /// True when the string table was cut off by `maxStrings`.
    let stringsTruncated: Bool
    /// Objective-C selector names from __TEXT,__objc_methname.
    let objcSelectors: [String]
    /// FairPlay encryption state from LC_ENCRYPTION_INFO(_64):
    /// `cryptid != 0` means the __TEXT segment is encrypted and
    /// static analysis of this image is impossible.
    let isFairPlayEncrypted: Bool
    /// True when an ARM64 `svc #0x80` instruction (0xD4001001) was
    /// found in a __TEXT section (direct syscall, bypassing
    /// libSystem wrappers).
    let hasDirectSyscall: Bool
    /// Number of `svc #0x80` instructions found (0 when none).
    let directSyscallCount: Int
    /// Raw LC_CODE_SIGNATURE payload, when present. The caller
    /// hands it to `IPAAuditCSBlobParser`; this struct never
    /// interprets it.
    let codeSignature: Data?
}

// MARK: - Parser

/// Bounds-checked Mach-O parser for 32-bit, 64-bit and fat
/// binaries. The upstream hard cap of 1,024 fat slices (anti
/// slice-bomb) is kept.
enum IPAAuditMachOParser {
    static let maxFatSlices = 1_024
    static let maxSymbols = 100_000
    static let maxStrings = 100_000
    static let maxCStringLength = 512

    /// Load-command values (from `<mach-o/loader.h>`).
    static let lcSegment: UInt32 = 0x1
    static let lcSymtab: UInt32 = 0x2
    static let lcLoadDylib: UInt32 = 0xc
    static let lcLoadWeakDylib: UInt32 = 0x18
    static let lcReexportDylib: UInt32 = 0x1f
    static let lcCodeSignature: UInt32 = 0x1d
    static let lcEncryptionInfo: UInt32 = 0x21
    static let lcSegment64: UInt32 = 0x19
    static let lcEncryptionInfo64: UInt32 = 0x2c

    /// ARM64 `svc #0x80` little-endian encoding.
    static let svc0x80: UInt32 = 0xD400_1001

    /// CPU types (from `<mach/machine.h>`).
    static let cpuTypeARM64: UInt32 = 0x0100_000C
    static let cpuTypeARM64_32: UInt32 = 0x0200_000C
    static let cpuTypeX86_64: UInt32 = 0x0100_0007

    /// Parses `data` as a thin or fat Mach-O and returns one report
    /// per slice. Fat binaries return the union of their slices:
    /// callers match rules against every slice so a second slice
    /// cannot hide evidence (anti multi-slice shadowing).
    static func parse(_ data: Data) throws -> [IPAAuditMachOReport] {
        let reader = IPAAuditDataReader(data: data)
        guard let magicBE = reader.uint32BE(at: 0) else {
            throw IPAAuditError(L("The file is too small to be a Mach-O binary."))
        }
        switch magicBE {
        case 0xcafe_babe, 0xcafe_babf:
            return try parseFat(reader)
        default:
            return [try parseThin(reader, baseOffset: 0, isFat: false, sliceCount: 1)]
        }
    }

    // MARK: Fat

    private static func parseFat(_ reader: IPAAuditDataReader) throws -> [IPAAuditMachOReport] {
        guard let sliceCount32 = reader.uint32BE(at: 4) else {
            throw IPAAuditError(L("The fat binary header is truncated."))
        }
        guard sliceCount32 >= 1, sliceCount32 <= UInt32(maxFatSlices) else {
            throw IPAAuditError(L("The fat binary declares an impossible slice count."))
        }
        let sliceCount = Int(sliceCount32)
        var reports: [IPAAuditMachOReport] = []
        reports.reserveCapacity(sliceCount)
        for index in 0..<sliceCount {
            let entryOffset = 8 + index * 20
            guard let offset = reader.uint32BE(at: entryOffset + 8),
                  let size = reader.uint32BE(at: entryOffset + 12) else {
                throw IPAAuditError(L("The fat binary slice table is truncated."))
            }
            let sliceOffset = Int(offset)
            let sliceSize = Int(size)
            guard sliceSize > 0, reader.contains(offset: sliceOffset, size: sliceSize) else {
                throw IPAAuditError(L("A fat binary slice lies outside the file."))
            }
            guard let sliceData = reader.subdata(offset: sliceOffset, size: sliceSize) else {
                throw IPAAuditError(L("A fat binary slice lies outside the file."))
            }
            let sliceReader = IPAAuditDataReader(data: sliceData)
            reports.append(try parseThin(sliceReader, baseOffset: 0, isFat: true, sliceCount: sliceCount))
        }
        return reports
    }

    // MARK: Thin

    private static func parseThin(
        _ reader: IPAAuditDataReader, baseOffset: Int, isFat: Bool, sliceCount: Int
    ) throws -> IPAAuditMachOReport {
        guard let magic = reader.uint32LE(at: baseOffset) else {
            throw IPAAuditError(L("The file is too small to be a Mach-O binary."))
        }
        let is64Bit: Bool
        switch magic {
        case 0xfeed_facf: is64Bit = true
        case 0xfeed_face: is64Bit = false
        default: throw IPAAuditError(L("The file is not a Mach-O binary."))
        }
        guard let cpuType = reader.uint32LE(at: baseOffset + 4),
              let cpuSubtype = reader.uint32LE(at: baseOffset + 8),
              let ncmds = reader.uint32LE(at: baseOffset + 16),
              let sizeofcmds = reader.uint32LE(at: baseOffset + 20) else {
            throw IPAAuditError(L("The Mach-O header is truncated."))
        }
        let headerSize = is64Bit ? 32 : 28
        let commandsEnd = baseOffset + headerSize + Int(sizeofcmds)
        guard ncmds <= 10_000,
              reader.contains(offset: baseOffset + headerSize, size: Int(sizeofcmds)),
              commandsEnd <= reader.count else {
            throw IPAAuditError(L("The Mach-O load commands lie outside the file."))
        }

        var linkedDylibs: [String] = []
        var symtab: (symoff: Int, nsyms: Int, stroff: Int, strsize: Int)?
        var textSections: [(offset: Int, size: Int)] = []
        var cstringSection: (offset: Int, size: Int)?
        var methnameSection: (offset: Int, size: Int)?
        var isFairPlayEncrypted = false
        var codeSignature: Data?
        var cursor = baseOffset + headerSize

        for _ in 0..<Int(ncmds) {
            guard let cmd = reader.uint32LE(at: cursor),
                  let cmdsize = reader.uint32LE(at: cursor + 4),
                  cmdsize >= 8,
                  reader.contains(offset: cursor, size: Int(cmdsize)),
                  cursor + Int(cmdsize) <= commandsEnd else {
                throw IPAAuditError(L("A Mach-O load command is truncated."))
            }
            switch cmd {
            case lcSegment, lcSegment64:
                let isSegment64 = (cmd == lcSegment64)
                let nsectsOffset = isSegment64 ? 64 : 48
                guard let nsects = reader.uint32LE(at: cursor + nsectsOffset) else {
                    throw IPAAuditError(L("A Mach-O segment command is truncated."))
                }
                guard nsects <= 1_000 else {
                    throw IPAAuditError(L("A Mach-O segment declares too many sections."))
                }
                let sectionSize = isSegment64 ? 80 : 68
                let sectionsStart = cursor + (isSegment64 ? 72 : 56)
                for sectionIndex in 0..<Int(nsects) {
                    let sectionOffset = sectionsStart + sectionIndex * sectionSize
                    guard reader.contains(offset: sectionOffset, size: sectionSize),
                          let sectname = cStringFromFixed(reader: reader, offset: sectionOffset, length: 16),
                          let segname = cStringFromFixed(reader: reader, offset: sectionOffset + 16, length: 16) else {
                        throw IPAAuditError(L("A Mach-O section header is truncated."))
                    }
                    let sizeOffset = isSegment64 ? sectionOffset + 40 : sectionOffset + 36
                    let fileOffsetOffset = isSegment64 ? sectionOffset + 48 : sectionOffset + 40
                    guard let sectionSizeValue = isSegment64
                            ? reader.uint64LE(at: sizeOffset).map({ Int($0) })
                            : reader.uint32LE(at: sizeOffset).map({ Int($0) }),
                          let fileOffset = reader.uint32LE(at: fileOffsetOffset).map({ Int($0) }) else {
                        throw IPAAuditError(L("A Mach-O section header is truncated."))
                    }
                    guard sectionSizeValue >= 0, fileOffset >= 0,
                          reader.contains(offset: fileOffset, size: sectionSizeValue) else {
                        throw IPAAuditError(L("A Mach-O section lies outside the file."))
                    }
                    if segname == "__TEXT" {
                        textSections.append((offset: fileOffset, size: sectionSizeValue))
                        if sectname == "__cstring" {
                            cstringSection = (offset: fileOffset, size: sectionSizeValue)
                        } else if sectname == "__objc_methname" {
                            methnameSection = (offset: fileOffset, size: sectionSizeValue)
                        }
                    }
                }
            case lcSymtab:
                guard let symoff = reader.uint32LE(at: cursor + 8),
                      let nsyms = reader.uint32LE(at: cursor + 12),
                      let stroff = reader.uint32LE(at: cursor + 16),
                      let strsize = reader.uint32LE(at: cursor + 20) else {
                    throw IPAAuditError(L("The symbol table command is truncated."))
                }
                symtab = (symoff: Int(symoff), nsyms: Int(nsyms), stroff: Int(stroff), strsize: Int(strsize))
            case lcLoadDylib, lcLoadWeakDylib, lcReexportDylib:
                guard let nameOffset = reader.uint32LE(at: cursor + 8) else {
                    throw IPAAuditError(L("A dylib load command is truncated."))
                }
                if let name = reader.cString(at: cursor + Int(nameOffset), maxLength: 1_024),
                   !name.isEmpty, !linkedDylibs.contains(name) {
                    linkedDylibs.append(name)
                }
            case lcEncryptionInfo, lcEncryptionInfo64:
                guard let cryptid = reader.uint32LE(at: cursor + 16) else {
                    throw IPAAuditError(L("The encryption info command is truncated."))
                }
                if cryptid != 0 { isFairPlayEncrypted = true }
            case lcCodeSignature:
                guard let dataoff = reader.uint32LE(at: cursor + 8),
                      let datasize = reader.uint32LE(at: cursor + 12) else {
                    throw IPAAuditError(L("The code signature command is truncated."))
                }
                guard Int(datasize) >= 0, reader.contains(offset: Int(dataoff), size: Int(datasize)) else {
                    throw IPAAuditError(L("The code signature lies outside the file."))
                }
                codeSignature = reader.subdata(offset: Int(dataoff), size: Int(datasize))
            default:
                break
            }
            cursor += Int(cmdsize)
        }

        let symbols = try readSymbols(reader: reader, symtab: symtab, is64Bit: is64Bit)
        let cstrings = readCStringSection(reader: reader, section: cstringSection)
        let objcSelectors = readCStringSection(reader: reader, section: methnameSection)
        let (hasDirectSyscall, directSyscallCount) = countDirectSyscalls(
            reader: reader, sections: textSections, architectureIsARM64: cpuType == cpuTypeARM64 || cpuType == cpuTypeARM64_32)

        return IPAAuditMachOReport(
            architecture: architectureName(cpuType: cpuType, cpuSubtype: cpuSubtype),
            is64Bit: is64Bit,
            isFat: isFat,
            sliceCount: sliceCount,
            linkedDylibs: linkedDylibs,
            symbols: symbols.values,
            symbolsTruncated: symbols.truncated,
            cstrings: cstrings.values,
            stringsTruncated: cstrings.truncated,
            objcSelectors: objcSelectors.values,
            isFairPlayEncrypted: isFairPlayEncrypted,
            hasDirectSyscall: hasDirectSyscall,
            directSyscallCount: directSyscallCount,
            codeSignature: codeSignature)
    }

    // MARK: Symbol + string tables

    private static func readSymbols(
        reader: IPAAuditDataReader,
        symtab: (symoff: Int, nsyms: Int, stroff: Int, strsize: Int)?,
        is64Bit: Bool
    ) throws -> (values: [String], truncated: Bool) {
        guard let symtab else { return ([], false) }
        guard symtab.nsyms >= 0, symtab.nsyms <= maxSymbols * 2,
              symtab.stroff >= 0, symtab.strsize >= 0,
              reader.contains(offset: symtab.stroff, size: symtab.strsize) else {
            throw IPAAuditError(L("The symbol table lies outside the file."))
        }
        let entrySize = is64Bit ? 16 : 12
        guard symtab.symoff >= 0,
              reader.contains(offset: symtab.symoff, size: symtab.nsyms * entrySize) else {
            throw IPAAuditError(L("The symbol table lies outside the file."))
        }
        var values: [String] = []
        var seen = Set<String>()
        var truncated = false
        for index in 0..<symtab.nsyms {
            if values.count >= maxSymbols { truncated = true; break }
            let entryOffset = symtab.symoff + index * entrySize
            guard let strx = reader.uint32LE(at: entryOffset) else { break }
            guard strx != 0, Int(strx) < symtab.strsize else { continue }
            let stringOffset = symtab.stroff + Int(strx)
            guard let name = reader.cString(at: stringOffset, maxLength: maxCStringLength),
                  !name.isEmpty, seen.insert(name).inserted else { continue }
            values.append(name)
        }
        return (values, truncated)
    }

    /// Splits a `__cstring`-style section (NUL-separated strings)
    /// into its strings, capped at `maxStrings`.
    private static func readCStringSection(
        reader: IPAAuditDataReader, section: (offset: Int, size: Int)?
    ) -> (values: [String], truncated: Bool) {
        guard let section, section.size > 0,
              let bytes = reader.subdata(offset: section.offset, size: section.size) else {
            return ([], false)
        }
        var values: [String] = []
        var seen = Set<String>()
        var truncated = false
        var start = bytes.startIndex
        while start < bytes.endIndex {
            if values.count >= maxStrings { truncated = true; break }
            guard let nul = bytes[start...].firstIndex(of: 0) else { break }
            if nul > start {
                let slice = bytes[start..<nul]
                if slice.count <= maxCStringLength,
                   let text = String(bytes: slice, encoding: .utf8),
                   !text.isEmpty, seen.insert(text).inserted {
                    values.append(text)
                }
            }
            start = bytes.index(after: nul)
        }
        return (values, truncated)
    }

    /// Counts ARM64 `svc #0x80` instructions in the __TEXT
    /// sections of ARM64 slices. Non-ARM slices are never scanned:
    /// the encoding is ARM64-specific, so scanning x86_64 bytes
    /// for it would only produce false positives.
    private static func countDirectSyscalls(
        reader: IPAAuditDataReader, sections: [(offset: Int, size: Int)], architectureIsARM64: Bool
    ) -> (hasDirectSyscall: Bool, count: Int) {
        guard architectureIsARM64 else { return (false, 0) }
        var count = 0
        for section in sections {
            guard section.size >= 4,
                  let bytes = reader.subdata(offset: section.offset, size: section.size) else { continue }
            var index = bytes.startIndex
            let last = bytes.index(bytes.endIndex, offsetBy: -3)
            while index <= last {
                if reader.uint32LE(at: section.offset + (index - bytes.startIndex)) == svc0x80 {
                    count += 1
                    index = bytes.index(index, offsetBy: 4)
                } else {
                    index = bytes.index(after: index)
                }
            }
        }
        return (count > 0, count)
    }

    private static func cStringFromFixed(reader: IPAAuditDataReader, offset: Int, length: Int) -> String? {
        guard reader.contains(offset: offset, size: length),
              let bytes = reader.subdata(offset: offset, size: length) else { return nil }
        let end = bytes.firstIndex(of: 0) ?? bytes.endIndex
        return String(bytes: bytes[bytes.startIndex..<end], encoding: .utf8)
    }

    private static func architectureName(cpuType: UInt32, cpuSubtype: UInt32) -> String {
        switch cpuType {
        case cpuTypeARM64:
            // CPU_SUBTYPE_ARM64E == 2.
            return cpuSubtype == 2 ? "arm64e" : "arm64"
        case cpuTypeARM64_32:
            return "arm64_32"
        case cpuTypeX86_64:
            return "x86_64"
        default:
            return "cpu_0x\(String(cpuType, radix: 16))"
        }
    }
}
