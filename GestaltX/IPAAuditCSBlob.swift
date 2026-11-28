// SPDX-License-Identifier: GPL-3.0-only
// IPA Audit — dual-slot code signature (CSBlob) parser (W3).
//
// Ported from the design of Kianuni/WQGuard v1.3.6
// (`Sources/WQGuardCore/MachO/CSBlobParser.swift`, MIT, Copyright
// (c) 2026 WQGuard Contributors) — see W3NOTICES.md. Compact
// re-implementation for LilaShift, not a copy of the upstream file.
// Kept from upstream: SuperBlob / CodeDirectory / blob magic
// values, slot numbers (0 CodeDirectory, 5 XML entitlements,
// 7 DER entitlements, 0x10000 CMS), the anti-shadowing merge
// (string-array union; booleans OR, except
// `com.apple.private.security.container-required` which ANDs; DER
// wins for other scalars), and the unaligned byte-safe
// big-endian reader. LilaShift does NOT verify the CMS
// certificate chain: `hasCMSSignature` reports presence only,
// and the report never claims a signature is cryptographically
// verified.
//
// Read-only: every read is bounds-checked; a malformed blob is an
// error, never a partial guess.
import Foundation

/// The parsed code signature of one Mach-O image.
struct IPAAuditCodeSignature: Equatable, Sendable, Codable {
    /// Slot 5 (XML plist) was present.
    let hasXMLEntitlements: Bool
    /// Slot 7 (DER) was present.
    let hasDEREntitlements: Bool
    /// The merged entitlement dictionary, as sorted key/value
    /// pairs. Values are rendered as plain strings so the struct
    /// stays `Codable`-friendly for the report (the raw plist
    /// dictionary itself is `[String: Any]` and cannot be encoded
    /// directly). DER keys are OID dotted strings: Apple does not
    /// publish a CoreEntitlements OID-to-name table, so this
    /// parser never invents entitlement names for DER entries.
    let mergedEntitlements: [IPAAuditEntitlement]
    /// App Group identifiers from the merged entitlements.
    let appGroups: [String]
    /// The CodeDirectory `ident` string, when present.
    let codeDirectoryIdent: String?
    /// `CS_ADHOC` (0x2) was set in CodeDirectory flags.
    let isAdHoc: Bool
    /// A CMS signature blob (slot 0x10000) was present. Presence
    /// only — the chain is NOT verified (see the file header).
    let hasCMSSignature: Bool

    /// True when neither entitlement slot was present.
    var hasNoEntitlements: Bool { !hasXMLEntitlements && !hasDEREntitlements }
}

/// One merged entitlement, rendered for the report.
struct IPAAuditEntitlement: Equatable, Sendable, Codable {
    let key: String
    /// The value rendered as text (`true` / `false`, a number, a
    /// string, or `[a, b]` for string arrays).
    let value: String
    /// Which slot the value came from: "XML", "DER", or "XML+DER".
    let source: String
}

/// Dual-slot CSBlob parser: SuperBlob index → CodeDirectory +
/// slot 5 XML plist + slot 7 DER, merged with the upstream
/// anti-shadowing rules.
enum IPAAuditCSBlobParser {
    /// SuperBlob magic: 0xfade0cc0 (CSBLOB_EMBEDDED_SIGNATURE).
    static let superBlobMagic: UInt32 = 0xfade_0cc0
    /// CodeDirectory magic: 0xfade0c02 (CSMAGIC_CODEDIRECTORY).
    static let codeDirectoryMagic: UInt32 = 0xfade_0c02
    /// CMS BlobWrapper magic: 0xfade0b01 (CSMAGIC_BLOBWRAPPER).
    static let blobWrapperMagic: UInt32 = 0xfade_0b01
    /// Slot 5 entitlements magic: 0xfade7171 (CSBLOB_ENTITLEMENTS).
    static let entitlementXMLMagic: UInt32 = 0xfade_7171
    /// Slot 7 entitlements magic: 0xfade7172
    /// (CSBLOB_DER_ENTITLEMENTS).
    static let entitlementDERMagic: UInt32 = 0xfade_7172
    /// CodeDirectory ad-hoc flag: 0x00000002 (CS_ADHOC).
    static let csAdHocFlag: UInt32 = 0x0000_0002

    static let slotCodeDirectory: UInt32 = 0x0
    static let slotEntitlementsXML: UInt32 = 0x5
    static let slotEntitlementsDER: UInt32 = 0x7
    static let slotCMSSignature: UInt32 = 0x10000

    static let appGroupsKey = "com.apple.security.application-groups"
    static let containerRequiredKey = "com.apple.private.security.container-required"

    /// Parses an LC_CODE_SIGNATURE payload. Throws when the
    /// SuperBlob header is malformed or a present slot cannot be
    /// decoded; a missing entitlements slot is not an error (the
    /// result reports `hasNoEntitlements`).
    static func parse(_ data: Data) throws -> IPAAuditCodeSignature {
        let parsed = try parseDictionaries(data)
        let merged = mergeEntitlementDictionaries(parsed.xml ?? [:], parsed.der ?? [:])
        let rendered = renderEntitlements(
            merged, xmlKeys: Set(parsed.xml?.keys ?? []), derKeys: Set(parsed.der?.keys ?? []))
        let appGroups = (merged[appGroupsKey] as? [String]) ?? []
        return IPAAuditCodeSignature(
            hasXMLEntitlements: parsed.xml != nil,
            hasDEREntitlements: parsed.der != nil,
            mergedEntitlements: rendered,
            appGroups: appGroups,
            codeDirectoryIdent: parsed.codeDirectoryIdent,
            isAdHoc: parsed.isAdHoc,
            hasCMSSignature: parsed.hasCMSSignature)
    }

    /// The slot-level parse behind `parse`: the raw XML and DER
    /// dictionaries plus the CodeDirectory / CMS facts. The
    /// scanner uses this directly so entitlements from several
    /// fat slices merge with the anti-shadowing rules instead of
    /// being flattened to display strings first.
    struct ParsedSlots {
        let xml: [String: Any]?
        let der: [String: Any]?
        let codeDirectoryIdent: String?
        let isAdHoc: Bool
        let hasCMSSignature: Bool
    }

    static func parseDictionaries(_ data: Data) throws -> ParsedSlots {
        let reader = IPAAuditDataReader(data: data)
        guard let magic = reader.uint32BE(at: 0), magic == superBlobMagic else {
            throw IPAAuditError(L("The code signature is not a SuperBlob."))
        }
        guard let length = reader.uint32BE(at: 4),
              let count = reader.uint32BE(at: 8),
              count <= 10_000 else {
            throw IPAAuditError(L("The code signature header is truncated."))
        }
        guard Int(length) <= data.count, Int(length) >= 12 else {
            throw IPAAuditError(L("The code signature declares a length outside the file."))
        }
        let indexEnd = 12 + Int(count) * 8
        guard indexEnd <= data.count else {
            throw IPAAuditError(L("The code signature index is truncated."))
        }

        var xmlEntitlements: [String: Any]?
        var derEntitlements: [String: Any]?
        var codeDirectoryIdent: String?
        var isAdHoc = false
        var hasCMSSignature = false

        for index in 0..<Int(count) {
            let entryOffset = 12 + index * 8
            guard let type = reader.uint32BE(at: entryOffset),
                  let blobOffset = reader.uint32BE(at: entryOffset + 4) else {
                throw IPAAuditError(L("The code signature index is truncated."))
            }
            let offset = Int(blobOffset)
            guard let blobMagic = reader.uint32BE(at: offset),
                  let blobLength = reader.uint32BE(at: offset + 4),
                  Int(blobLength) >= 8,
                  reader.contains(offset: offset, size: Int(blobLength)) else {
                throw IPAAuditError(L("A code signature blob lies outside the file."))
            }
            let payloadOffset = offset + 8
            let payloadLength = Int(blobLength) - 8
            switch type {
            case slotCodeDirectory:
                guard blobMagic == codeDirectoryMagic else { continue }
                if let parsed = parseCodeDirectory(reader: reader, offset: offset) {
                    codeDirectoryIdent = parsed.ident
                    isAdHoc = parsed.isAdHoc
                }
            case slotEntitlementsXML:
                guard blobMagic == entitlementXMLMagic,
                      let payload = reader.subdata(offset: payloadOffset, size: payloadLength) else { continue }
                xmlEntitlements = try parseXMLPlist(payload)
            case slotEntitlementsDER:
                guard blobMagic == entitlementDERMagic,
                      let payload = reader.subdata(offset: payloadOffset, size: payloadLength) else { continue }
                derEntitlements = try parseDEREntitlements(payload)
            case slotCMSSignature:
                if blobMagic == blobWrapperMagic { hasCMSSignature = true }
            default:
                break
            }
        }

        return ParsedSlots(
            xml: xmlEntitlements,
            der: derEntitlements,
            codeDirectoryIdent: codeDirectoryIdent,
            isAdHoc: isAdHoc,
            hasCMSSignature: hasCMSSignature)
    }

    // MARK: CodeDirectory

    /// CodeDirectory layout (big-endian): magic(4) length(4)
    /// version(4) flags(4) hashOffset(4) identOffset(4) ...
    private static func parseCodeDirectory(
        reader: IPAAuditDataReader, offset: Int
    ) -> (ident: String?, isAdHoc: Bool)? {
        guard let flags = reader.uint32BE(at: offset + 12),
              let identOffset = reader.uint32BE(at: offset + 20) else { return nil }
        let ident = reader.cString(at: offset + Int(identOffset), maxLength: 1_024)
        return (ident, flags & csAdHocFlag != 0)
    }

    // MARK: Slot 5 — XML plist

    private static func parseXMLPlist(_ data: Data) throws -> [String: Any] {
        let plist: Any
        do {
            plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            throw IPAAuditError(L("The XML entitlements plist is malformed."))
        }
        guard let dict = plist as? [String: Any] else {
            throw IPAAuditError(L("The XML entitlements are not a dictionary."))
        }
        return dict
    }

    // MARK: Slot 7 — DER (CoreEntitlements)

    /// Generic ASN.1 DER decoder for the CoreEntitlements slot,
    /// following the shape of upstream's `ASN1DERDecoder` +
    /// `toDictionary`: the whole payload is decoded into a node
    /// tree (recursion depth capped at 32), then walked for
    /// (key, value) pairs. A key is an OID node — decoded to its
    /// dotted string — or a string node; values are booleans,
    /// integers, strings, string arrays or nested dictionaries.
    /// Keys are OID dotted strings: Apple does not publish a
    /// CoreEntitlements OID-to-name table, so this parser never
    /// invents entitlement names for DER entries. Anything that
    /// does not fit a pair shape is skipped, never guessed.
    static func parseDEREntitlements(_ data: Data) throws -> [String: Any] {
        guard !data.isEmpty else { return [:] }
        let reader = IPAAuditDataReader(data: data)
        let (root, _) = try decodeDERNode(reader: reader, offset: 0, depth: 0)
        return derToDictionary(root)
    }

    /// One decoded DER node.
    indirect enum IPAAuditDERNode {
        case boolean(Bool)
        case integer(Int64)
        case string(String)
        case data(Data)
        case sequence([IPAAuditDERNode])
        case set([IPAAuditDERNode])
        case other(tag: UInt8, data: Data)
    }

    private static let derMaxDepth = 32

    /// Decodes one node at `offset` and returns it with the
    /// offset just past it. BER indefinite length (0x80) is
    /// rejected: it is forbidden in DER (ITU-T X.690 §10.1).
    private static func decodeDERNode(
        reader: IPAAuditDataReader, offset: Int, depth: Int
    ) throws -> (IPAAuditDERNode, Int) {
        guard depth <= derMaxDepth else {
            throw IPAAuditError(L("The DER entitlements exceed the recursion limit."))
        }
        let tlv = try readTLV(reader: reader, offset: offset)
        let end = tlv.valueOffset + tlv.valueLength
        guard let valueData = reader.subdata(offset: tlv.valueOffset, size: tlv.valueLength) else {
            throw IPAAuditError(L("The DER entitlements are truncated."))
        }
        switch tlv.tag {
        case 0x01: // BOOLEAN
            guard tlv.valueLength == 1, let byte = reader.uint8(at: tlv.valueOffset) else {
                throw IPAAuditError(L("The DER entitlements have a malformed BOOLEAN."))
            }
            return (.boolean(byte != 0), end)
        case 0x02: // INTEGER (two's complement, up to 64 bits)
            guard tlv.valueLength >= 1 else {
                throw IPAAuditError(L("The DER entitlements have a malformed INTEGER."))
            }
            let isNegative = (valueData[valueData.startIndex] & 0x80) != 0
            var value: Int64 = isNegative ? -1 : 0
            var anyNonZero = false
            for byte in valueData {
                if byte != 0 { anyNonZero = true }
                value = (value << 8) | Int64(byte)
            }
            if value == 0, anyNonZero {
                value = isNegative ? -1 : 1
            }
            return (.integer(value), end)
        case 0x06: // OBJECT IDENTIFIER → dotted string key
            guard let oid = decodeOID(valueData) else {
                throw IPAAuditError(L("The DER entitlements have a malformed OID."))
            }
            return (.string(oid), end)
        case 0x0C, 0x13, 0x14, 0x15, 0x16, 0x19, 0x1A, 0x1B: // string types
            return (.string(String(decoding: valueData, as: UTF8.self)), end)
        case 0x1E: // BMPString (UTF-16BE)
            if let text = String(data: valueData, encoding: .utf16BigEndian) {
                return (.string(text), end)
            }
            return (.data(valueData), end)
        case 0x04: // OCTET STRING
            return (.data(valueData), end)
        case 0x05: // NULL
            return (.boolean(true), end)
        case 0x30, 0x31: // SEQUENCE / SET
            var children: [IPAAuditDERNode] = []
            var cursor = tlv.valueOffset
            while cursor < end {
                let (child, next) = try decodeDERNode(reader: reader, offset: cursor, depth: depth + 1)
                children.append(child)
                guard next > cursor else {
                    throw IPAAuditError(L("The DER entitlements are truncated."))
                }
                cursor = next
            }
            return (tlv.tag == 0x30 ? .sequence(children) : .set(children), end)
        default:
            return (.other(tag: tlv.tag, data: valueData), end)
        }
    }

    /// Walks a decoded node tree for (key, value) pairs, mirroring
    /// upstream's `toDictionary`: a node is a pair when it is a
    /// 2-element sequence/set whose first child is a string; a
    /// node whose children are all pairs contributes all of them;
    /// an alternating string/value child list contributes its
    /// pairs; otherwise the walk recurses into the children.
    private static func derToDictionary(_ node: IPAAuditDERNode) -> [String: Any] {
        var dict: [String: Any] = [:]

        func asPair(_ node: IPAAuditDERNode) -> (String, IPAAuditDERNode)? {
            switch node {
            case .sequence(let pair), .set(let pair):
                if pair.count == 2, case .string(let key) = pair[0] {
                    return (key, pair[1])
                }
                return nil
            default:
                return nil
            }
        }

        func isAlternatingKeyValueList(_ items: [IPAAuditDERNode], requireNonStringValue: Bool) -> Bool {
            guard items.count >= 4, items.count % 2 == 0 else { return false }
            var sawNonStringValue = false
            for index in stride(from: 0, to: items.count, by: 2) {
                guard case .string(let key) = items[index], !key.isEmpty else { return false }
                if case .string = items[index + 1] {
                    continue
                }
                sawNonStringValue = true
            }
            return !requireNonStringValue || sawNonStringValue
        }

        func convertValue(_ node: IPAAuditDERNode) -> Any {
            switch node {
            case .boolean(let value): return value
            case .integer(let value): return value
            case .string(let value): return value
            case .data(let value): return value
            case .sequence(let items), .set(let items):
                if !items.isEmpty {
                    let pairs = items.compactMap(asPair)
                    if pairs.count == items.count {
                        var sub: [String: Any] = [:]
                        for (key, value) in pairs {
                            sub = mergeEntitlementDictionaries(sub, [key: convertValue(value)])
                        }
                        return sub
                    }
                    if isAlternatingKeyValueList(items, requireNonStringValue: true) {
                        var sub: [String: Any] = [:]
                        for index in stride(from: 0, to: items.count, by: 2) {
                            if case .string(let key) = items[index] {
                                sub = mergeEntitlementDictionaries(sub, [key: convertValue(items[index + 1])])
                            }
                        }
                        return sub
                    }
                }
                return items.map(convertValue)
            case .other(_, let value): return value
            }
        }

        func walk(_ node: IPAAuditDERNode) {
            switch node {
            case .sequence(let children), .set(let children):
                if let (key, value) = asPair(node) {
                    dict = mergeEntitlementDictionaries(dict, [key: convertValue(value)])
                    return
                }
                let pairs = children.compactMap(asPair)
                if !children.isEmpty, pairs.count == children.count {
                    for (key, value) in pairs {
                        dict = mergeEntitlementDictionaries(dict, [key: convertValue(value)])
                    }
                    return
                }
                if isAlternatingKeyValueList(children, requireNonStringValue: false) {
                    for index in stride(from: 0, to: children.count, by: 2) {
                        if case .string(let key) = children[index] {
                            dict = mergeEntitlementDictionaries(dict, [key: convertValue(children[index + 1])])
                        }
                    }
                    return
                }
                for child in children {
                    if let (key, value) = asPair(child) {
                        dict = mergeEntitlementDictionaries(dict, [key: convertValue(value)])
                    } else {
                        walk(child)
                    }
                }
            default:
                break
            }
        }

        walk(node)
        return dict
    }

    /// A decoded TLV: tag byte, value offset and value length.
    /// Multi-byte high tags (ITU-T X.690) are supported; the tag
    /// returned is the first-byte class + constructed bit plus the
    /// decoded tag number in the low bits for the tags this parser
    /// cares about (0x30, 0x31, 0x06, 0x01, 0x02, 0x0C, 0x13,
    /// 0x16, 0x04, 0x05). Long-form lengths are capped at 4 length
    /// bytes to bound the read.
    private struct DERTLV {
        let tag: UInt8
        let valueOffset: Int
        let valueLength: Int
    }

    private static func readTLV(reader: IPAAuditDataReader, offset: Int) throws -> DERTLV {
        guard let first = reader.uint8(at: offset) else {
            throw IPAAuditError(L("The DER entitlements are truncated."))
        }
        var tag = first
        var cursor = offset + 1
        if first & 0x1F == 0x1F {
            // High-tag-number form: continuation bytes until the
            // high bit clears. Only the low 7 bits of the last
            // byte are kept; absurd tag numbers are rejected.
            var tagNumber = 0
            var bytes = 0
            while true {
                guard let byte = reader.uint8(at: cursor), bytes < 4 else {
                    throw IPAAuditError(L("The DER entitlements have a malformed tag."))
                }
                cursor += 1
                bytes += 1
                tagNumber = (tagNumber << 7) | Int(byte & 0x7F)
                if byte & 0x80 == 0 { break }
            }
            guard tagNumber <= 0xFF else {
                throw IPAAuditError(L("The DER entitlements have a malformed tag."))
            }
            tag = (first & 0xE0) | UInt8(tagNumber)
        }
        guard let lengthByte = reader.uint8(at: cursor) else {
            throw IPAAuditError(L("The DER entitlements are truncated."))
        }
        cursor += 1
        if lengthByte == 0x80 {
            // BER indefinite length is forbidden in DER.
            throw IPAAuditError(L("The DER entitlements use forbidden indefinite length."))
        }
        let valueLength: Int
        if lengthByte & 0x80 == 0 {
            valueLength = Int(lengthByte)
        } else {
            let lengthBytes = Int(lengthByte & 0x7F)
            guard lengthBytes >= 1, lengthBytes <= 4 else {
                throw IPAAuditError(L("The DER entitlements have a malformed length."))
            }
            var length = 0
            for index in 0..<lengthBytes {
                guard let byte = reader.uint8(at: cursor + index) else {
                    throw IPAAuditError(L("The DER entitlements are truncated."))
                }
                length = (length << 8) | Int(byte)
            }
            cursor += lengthBytes
            valueLength = length
        }
        guard valueLength >= 0, reader.contains(offset: cursor, size: valueLength) else {
            throw IPAAuditError(L("The DER entitlements are truncated."))
        }
        return DERTLV(tag: tag, valueOffset: cursor, valueLength: valueLength)
    }

    /// Decodes an OID content octets value to its dotted string
    /// (first byte = 40 * arc0 + arc1, then base-128 arcs).
    static func decodeOID(_ data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        var arcs: [Int] = []
        let first = Int(data[0])
        arcs.append(first / 40)
        arcs.append(first % 40)
        var value = 0
        var index = 1
        while index < data.count {
            let byte = data[index]
            index += 1
            value = (value << 7) | Int(byte & 0x7F)
            if byte & 0x80 == 0 {
                arcs.append(value)
                value = 0
            }
        }
        guard index == data.count else { return nil }
        return arcs.map(String.init).joined(separator: ".")
    }

    // MARK: Merge (anti-shadowing)

    /// Merges the XML (base) and DER (incoming) entitlement
    /// dictionaries without letting a benign placeholder shadow an
    /// active privilege — the upstream WQGuard rule:
    /// string arrays are deduplicated unions; boolean scalars OR
    /// together, except `container-required` which ANDs (its
    /// active value is `false`); other scalars prefer the DER
    /// value, which XNU/AMFI prioritizes over XML.
    static func mergeEntitlementDictionaries(
        _ base: [String: Any], _ incoming: [String: Any]
    ) -> [String: Any] {
        var result = base
        for (key, newValue) in incoming {
            if key == appGroupsKey {
                let oldGroups = (result[key] as? [String]) ?? []
                let newGroups = (newValue as? [String]) ?? []
                var union = oldGroups
                for group in newGroups where !union.contains(group) {
                    union.append(group)
                }
                if !union.isEmpty { result[key] = union }
                continue
            }
            if let oldValue = result[key],
               isInactivePlaceholder(key: key, value: oldValue),
               !isInactivePlaceholder(key: key, value: newValue) {
                result[key] = newValue
                continue
            }
            if let newBool = scalarBool(newValue), let oldValue = result[key], let oldBool = scalarBool(oldValue) {
                if key == containerRequiredKey {
                    result[key] = oldBool && newBool
                } else {
                    result[key] = oldBool || newBool
                }
                continue
            }
            if let oldStrings = result[key] as? [String], let newStrings = newValue as? [String] {
                var union = oldStrings
                for item in newStrings where !union.contains(item) {
                    union.append(item)
                }
                result[key] = union
                continue
            }
            result[key] = newValue
        }
        return result
    }

    private static func scalarBool(_ value: Any?) -> Bool? {
        guard let value else { return nil }
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        if let int = value as? Int { return int != 0 }
        if let int64 = value as? Int64 { return int64 != 0 }
        return nil
    }

    /// A value that carries no active privilege: `false` (or 0 /
    /// empty string / empty array) — except for
    /// `container-required`, where `true` is the inactive value.
    private static func isInactivePlaceholder(key: String, value: Any) -> Bool {
        if let bool = scalarBool(value) {
            return key == containerRequiredKey ? bool : !bool
        }
        if let string = value as? String {
            return string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if let array = value as? [Any] {
            if array.isEmpty { return true }
            let strings = array.compactMap { $0 as? String }
            if strings.count == array.count {
                return strings.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            }
            return false
        }
        return false
    }

    static func renderEntitlements(
        _ merged: [String: Any], xmlKeys: Set<String>, derKeys: Set<String>
    ) -> [IPAAuditEntitlement] {
        merged.keys.sorted().map { key in
            let value = merged[key]
            let source: String
            switch (xmlKeys.contains(key), derKeys.contains(key)) {
            case (true, true): source = "XML+DER"
            case (true, false): source = "XML"
            case (false, true): source = "DER"
            case (false, false): source = "?"
            }
            return IPAAuditEntitlement(key: key, value: renderValue(value), source: source)
        }
    }

    private static func renderValue(_ value: Any?) -> String {
        switch value {
        case let number as NSNumber:
            // Plist booleans arrive as NSNumber with objCType "c";
            // a plain `as Bool` cast would also match integer 1,
            // so the type code decides, not the value.
            if String(cString: number.objCType) == "c" {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        case let string as String: return string
        case let strings as [String]: return "[" + strings.joined(separator: ", ") + "]"
        case let array as [Any]: return "[" + array.map { renderValue($0) }.joined(separator: ", ") + "]"
        case let data as Data: return "data(\(data.count) bytes)"
        case nil: return "null"
        default: return String(describing: value)
        }
    }
}
