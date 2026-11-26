import Foundation
import XCTest
@testable import GestaltX

/// Offline tests for the Face ID recovery (A1, upstream GestaltX
/// #128/#146): restoring only the four hardware-identity fields
/// (product type, hardware board, CPU, model number) from a verified
/// same-device backup, keeping AI/region changes; the extended CPU
/// table (iPhone 16/17/Air, so the user's iPhone Air iPhone18,4 is
/// covered); and the fail-closed rejections (unknown models, wrong
/// CPU, foreign backup). The kernel physical identity
/// (`GXCopyPhysicalHardwareIdentity`) is device-only; these tests pass
/// the physical product/board explicitly, which is exactly what the
/// manager supplies from the kernel. No device or signing is needed:
/// the store runs against a temporary directory.
final class FaceIDRecoveryTests: XCTestCase {
    /// The user's iPhone Air board, as a fixture value. The restore
    /// only requires the backup's board to match the physical board
    /// passed in (case-insensitive); the value itself is not asserted
    /// against real hardware here.
    static let airBoard = "D73AP"
    static let airSerial = "SERIAL-AIR-FIXTURE"

    /// A document on the shared fixture cache (same CacheUUID,
    /// CacheVersion and CacheData bytes for every document built by
    /// this helper, so the layout gate passes and only the identity
    /// fields vary). `aiKey` sets the `ai` CacheExtra key, to prove a
    /// restore keeps it.
    static func document(productType: String, hardwareModel: String, cpu: String,
                         modelNumber: String, serial: String = airSerial,
                         aiKey: Bool = false, regionCode: String? = nil) throws -> GestaltDocument {
        let layout = MobileGestaltCacheLayout.originalProfile
        var cache = Data(count: layout.byteCount)
        cache[layout.greenTeaOffset] = 1
        cache[layout.notGreenTeaOffset] = 0
        cache[layout.validityOffset(for: layout.greenTeaIndex)] = 1
        cache[layout.validityOffset(for: layout.notGreenTeaIndex)] = 1
        var extra: [String: Any] = [
            GestaltKeys.productType: productType,
            GestaltKeys.hardwareModel: hardwareModel,
            GestaltKeys.cpu: cpu,
            GestaltKeys.modelNumber: modelNumber,
            "SerialNumber": serial,
            "UniqueDeviceID": "fixture-udid",
            "UniqueChipID": NSNumber(value: 12345),
        ]
        if aiKey { extra["A62OafQ85EJAiiqKn4agtg"] = true }
        if let regionCode { extra[GestaltKeys.regionCode] = regionCode }
        return try GestaltDocument(data: PropertyListSerialization.data(fromPropertyList: [
            "CacheVersion": "24C5037i", "CacheUUID": layout.uuid,
            "CacheData": cache, "CacheExtra": extra,
        ], format: .binary, options: 0))
    }

    /// A store against a temporary directory, with `initial` as the
    /// live file. Loading it creates the initial backup the restore
    /// reads from. Returns the store, the directory (removed by the
    /// caller) and the device URL.
    static func storeWithDocument(_ initial: GestaltDocument) throws -> (GestaltFileStore, URL, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let deviceURL = directory.appendingPathComponent("com.apple.MobileGestalt.plist")
        try initial.encoded().write(to: deviceURL)
        let store = GestaltFileStore(deviceURL: deviceURL,
                                     backupDirectory: directory.appendingPathComponent("backups"),
                                     deviceID: "faceid-fixture", acquire: { 1 }, release: { _ in })
        return (store, directory, deviceURL)
    }

    /// A store against a temporary directory, with the original
    /// (factory) Air document as the live file.
    static func storeWithOriginal() throws -> (GestaltFileStore, URL, URL) {
        let original = try document(productType: "iPhone18,4", hardwareModel: airBoard,
                                    cpu: "t8150", modelNumber: "A3518")
        return try storeWithDocument(original)
    }

    /// Writes `document` to the live file and builds the device
    /// snapshot the store expects for it.
    static func liveSnapshot(_ document: GestaltDocument, at deviceURL: URL) throws -> DocumentSnapshot {
        let data = try document.encoded()
        try data.write(to: deviceURL)
        return DocumentSnapshot(data: data, document: document, source: .device, name: "device")
    }

    func testDeviceCPUTable() {
        // Upstream range (iPhone 11 through iPhone 15/15 Plus).
        XCTAssert(GestaltFileStore.deviceCPU(for: "iPhone12,1") == "t8030", "iPhone 11 is A13 t8030")
        XCTAssert(GestaltFileStore.deviceCPU(for: "iPhone13,2") == "t8101", "iPhone 13 is A14 t8101")
        XCTAssert(GestaltFileStore.deviceCPU(for: "iPhone14,7") == "t8110", "iPhone 14 is A15 t8110")
        XCTAssert(GestaltFileStore.deviceCPU(for: "iPhone15,4") == "t8120", "iPhone 15 is A16 t8120")
        // Extended range (iPhone 16/17/Air) — the user's iPhone Air
        // iPhone18,4 must be covered, or the recovery cannot run on it.
        XCTAssert(GestaltFileStore.deviceCPU(for: "iPhone16,2") == "t8130", "iPhone 15 Pro Max is A17 Pro t8130")
        XCTAssert(GestaltFileStore.deviceCPU(for: "iPhone17,1") == "t8140", "iPhone 16 Pro is A18 Pro t8140")
        XCTAssert(GestaltFileStore.deviceCPU(for: "iPhone17,5") == "t8140", "iPhone 16e is A18 t8140")
        XCTAssert(GestaltFileStore.deviceCPU(for: "iPhone18,4") == "t8150", "iPhone Air is A19 t8150")
        XCTAssert(GestaltFileStore.deviceCPU(for: "iPhone18,1") == "t8150", "iPhone 17 is A19 t8150")
        // Fail closed: iPhone 19,x (A20 Pro) has no verifiable CPID
        // yet, and unknown products are rejected, never guessed.
        XCTAssert(GestaltFileStore.deviceCPU(for: "iPhone19,7") == nil, "iPhone 19,x is rejected until its CPID is verified")
        XCTAssert(GestaltFileStore.deviceCPU(for: "iPhone99,9") == nil, "Unknown products are rejected")
        XCTAssert(GestaltFileStore.deviceCPU(for: "") == nil, "An empty product type is rejected")
    }

    func testHardwareIdentityKeys() {
        XCTAssert(GestaltKeys.hardwareIdentity == [GestaltKeys.productType, GestaltKeys.hardwareModel,
                                                    GestaltKeys.cpu, GestaltKeys.modelNumber],
                   "hardwareIdentity is exactly the four fields a spoof can break")
        XCTAssert(GestaltKeys.hardwareModel == "oYicEKzVTz4/CxxE05pEgQ", "hardwareModel key matches upstream")
        XCTAssert(GestaltKeys.cpu == "5pYKlGnYYBzGvAlIU8RjEQ", "cpu key matches upstream")
    }

    func testRestoreKeepsAIAndRegion() async throws {
        let (store, directory, deviceURL) = try Self.storeWithOriginal()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try await store.loadDevice()
        let record = try await store.backups().first!
        XCTAssert(record.source == .device && record.sha256 != nil, "Initial backup is a verifiable device backup")
        // Spoof the live file: product type, CPU and model number now
        // claim a native-AI iPhone 15 Pro Max, while the AI key stays
        // staged and the region stays LL.
        let spoofedDoc = try Self.document(productType: "iPhone16,2", hardwareModel: Self.airBoard,
                                           cpu: "t8130", modelNumber: "A3108", aiKey: true,
                                           regionCode: "LL")
        let expected = try Self.liveSnapshot(spoofedDoc, at: deviceURL)
        let result = try await store.restoreHardwareIdentity(from: record, expected: expected,
                                                             physicalProduct: "iPhone18,4",
                                                             physicalBoard: Self.airBoard)
        XCTAssert(result.document.extra[GestaltKeys.productType] as? String == "iPhone18,4",
                   "Restore puts the real product type back")
        XCTAssert(result.document.extra[GestaltKeys.cpu] as? String == "t8150",
                   "Restore puts the real CPU back")
        XCTAssert(result.document.extra[GestaltKeys.modelNumber] as? String == "A3518",
                   "Restore puts the real model number back")
        XCTAssert(result.document.extra[GestaltKeys.hardwareModel] as? String == Self.airBoard,
                   "Restore puts the real board back")
        XCTAssert(result.document.extra["A62OafQ85EJAiiqKn4agtg"] as? Bool == true,
                   "Restore keeps the staged AI key")
        XCTAssert(result.document.extra[GestaltKeys.regionCode] as? String == "LL",
                   "Restore keeps the LL region code")
        let live = try GestaltDocument(data: Data(contentsOf: deviceURL))
        XCTAssert(live.matches(result.document), "The device file holds the restored document")
    }

    func testRestoreRejectsUnknownModel() async throws {
        // The backup itself claims an iPhone 19,x whose CPID is not
        // verifiable: the table returns nil, so the restore must refuse
        // rather than guess a chip.
        let future = try Self.document(productType: "iPhone19,7", hardwareModel: Self.airBoard,
                                       cpu: "t8160", modelNumber: "A9999")
        let (store, directory, deviceURL) = try Self.storeWithDocument(future)
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try await store.loadDevice()
        let record = try await store.backups().first!
        let expected = try Self.liveSnapshot(future, at: deviceURL)
        do {
            _ = try await store.restoreHardwareIdentity(from: record, expected: expected,
                                                        physicalProduct: "iPhone19,7",
                                                        physicalBoard: Self.airBoard)
            XCTFail("An unknown model must be rejected, not restored")
        } catch is GestaltFailure { /* expected */ }
    }

    func testRestoreRejectsWrongCPU() async throws {
        // The backup claims the Air's product type but the wrong chip
        // (t8130 is the A17 Pro, not the A19): the backup's CPU must
        // match the table for its product type, or it is untrustworthy.
        let wrongCPU = try Self.document(productType: "iPhone18,4", hardwareModel: Self.airBoard,
                                         cpu: "t8130", modelNumber: "A3518")
        let (store, directory, deviceURL) = try Self.storeWithDocument(wrongCPU)
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try await store.loadDevice()
        let record = try await store.backups().first!
        let spoofed = try Self.document(productType: "iPhone16,2", hardwareModel: Self.airBoard,
                                        cpu: "t8130", modelNumber: "A3108")
        let expected = try Self.liveSnapshot(spoofed, at: deviceURL)
        do {
            _ = try await store.restoreHardwareIdentity(from: record, expected: expected,
                                                        physicalProduct: "iPhone18,4",
                                                        physicalBoard: Self.airBoard)
            XCTFail("A backup whose CPU does not match its product type must be rejected")
        } catch is GestaltFailure { /* expected */ }
    }

    func testRestoreRejectsForeignBackup() async throws {
        let (store, directory, deviceURL) = try Self.storeWithOriginal()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try await store.loadDevice()
        let record = try await store.backups().first!
        // The live file belongs to a different device (different
        // serial): the device-identity check must refuse it.
        let foreign = try Self.document(productType: "iPhone16,2", hardwareModel: Self.airBoard,
                                        cpu: "t8130", modelNumber: "A3108",
                                        serial: "SERIAL-OTHER-DEVICE")
        let expected = try Self.liveSnapshot(foreign, at: deviceURL)
        do {
            _ = try await store.restoreHardwareIdentity(from: record, expected: expected,
                                                        physicalProduct: "iPhone18,4",
                                                        physicalBoard: Self.airBoard)
            XCTFail("A backup from another device must be rejected")
        } catch is GestaltFailure { /* expected */ }
    }

    func testRestoreRejectsChangedCache() async throws {
        let (store, directory, deviceURL) = try Self.storeWithOriginal()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try await store.loadDevice()
        let record = try await store.backups().first!
        // Live file has the same identity fields but different
        // CacheData bytes (for example eSIM flags changed after the
        // backup): the restore refuses, so it cannot clobber unrelated
        // cache changes. A full backup restore is the path then.
        let layout = MobileGestaltCacheLayout.originalProfile
        var otherCache = Data(count: layout.byteCount)
        otherCache[layout.greenTeaOffset] = 0
        otherCache[layout.notGreenTeaOffset] = 1
        otherCache[layout.validityOffset(for: layout.greenTeaIndex)] = 1
        otherCache[layout.validityOffset(for: layout.notGreenTeaIndex)] = 1
        let changed = try GestaltDocument(data: PropertyListSerialization.data(fromPropertyList: [
            "CacheVersion": "24C5037i", "CacheUUID": layout.uuid,
            "CacheData": otherCache,
            "CacheExtra": [GestaltKeys.productType: "iPhone16,2", GestaltKeys.hardwareModel: Self.airBoard,
                           GestaltKeys.cpu: "t8130", GestaltKeys.modelNumber: "A3108",
                           "SerialNumber": Self.airSerial, "UniqueDeviceID": "fixture-udid",
                           "UniqueChipID": NSNumber(value: 12345)],
        ], format: .binary, options: 0))
        let expected = try Self.liveSnapshot(changed, at: deviceURL)
        do {
            _ = try await store.restoreHardwareIdentity(from: record, expected: expected,
                                                        physicalProduct: "iPhone18,4",
                                                        physicalBoard: Self.airBoard)
            XCTFail("A backup whose cache differs from the live cache must be rejected")
        } catch is GestaltFailure { /* expected */ }
    }

    func testRestoreAlreadyMatchesIsNoop() async throws {
        let (store, directory, _) = try Self.storeWithOriginal()
        defer { try? FileManager.default.removeItem(at: directory) }
        let loaded = try await store.loadDevice()
        let record = try await store.backups().first!
        let result = try await store.restoreHardwareIdentity(from: record, expected: loaded,
                                                             physicalProduct: "iPhone18,4",
                                                             physicalBoard: Self.airBoard)
        XCTAssert(result.document.matches(loaded.document), "No spoof: the restore is a no-op returning the loaded document")
    }
}
