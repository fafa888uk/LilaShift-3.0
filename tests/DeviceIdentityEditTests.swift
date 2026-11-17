import Foundation
import XCTest
@testable import GestaltX

final class DeviceIdentityEditTests: XCTestCase {
    struct Failure: Error { let message: String }
    final class Trace: @unchecked Sendable { var writes = 0; var acquisitions = 0 }
    func expect(_ condition: Bool, _ message: String) {
        XCTAssert(condition, message)
    }

    func testDeviceIdentityEdit() async throws {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: directory) }
        let device = directory.appendingPathComponent("device.plist")
        let backups = directory.appendingPathComponent("backups")
        let identifiers: [String: Any] = [
            "UniqueDeviceID": "01234567-89abcdef", "re6Zb+zwFKJNlkQTUeT+/w": "01234567-89abcdef",
            "SerialNumber": "SERIAL1234", "VasUgeSzVyHdB27g2XpN0g": "SERIAL1234",
            "UniqueChipID": NSNumber(value: UInt64.max), "TF31PAB6aO8KAbPyNKSxKA": NSNumber(value: UInt64.max)
        ]
        let bytes = try PropertyListSerialization.data(fromPropertyList: [
            "CacheExtra": identifiers, "CacheUUID": "current-layout", "CacheVersion": "current-version", "CacheData": Data([0, 1, 2])
        ], format: .binary, options: 0)
        try bytes.write(to: device)
        let trace = Trace()
        let store = GestaltFileStore(deviceURL: device, backupDirectory: backups, deviceID: "identity-edit-fixture",
                                     acquire: { trace.acquisitions += 1; return 1 }, release: { _ in },
                                     writeData: { data, url in trace.writes += 1; try data.write(to: url) })
        let initial = try await store.loadDevice()
        let record = try await store.backups().first!
        trace.acquisitions = 0
        let replacements: [Any?] = [nil, "different", NSNumber(value: 1), NSNumber(value: true)]
        for key in identifiers.keys.sorted() {
            for replacement in replacements {
                var edited = initial.document
                edited.set(replacement, for: key)
                for restore in [false, true] {
                    do {
                        _ = try await store.commit(edited, expected: initial, restoring: restore ? record : nil)
                        throw Failure(message: "A device identity edit was accepted: " + key)
                    } catch let failure as GestaltFailure {
                        expect(failure.key == "Device identity fields cannot be changed in the system plist. Open a local file to edit these fields.", "Reject at the device identity preflight")
                    } catch {
                        // Diagnostic (Stage 9 fix9): the commit path
                        // only throws GestaltFailure, so a different
                        // error here names the exact attempt that hit
                        // it instead of failing opaquely.
                        throw Failure(message: "Identity edit for key \(key) replacement \(String(describing: replacement)) restore=\(restore) threw unexpected error: \(error)")
                    }
                }
            }
        }
        // Textually different representations are edits, even if an import
        // identity normalizer would treat them as the same identifier.
        var normalized = initial.document
        normalized.set("01234567-89ABCDEF", for: "UniqueDeviceID")
        do {
            _ = try await store.commit(normalized, expected: initial)
            throw Failure(message: "Identifier normalization silently changed the system field")
        } catch is GestaltFailure {}
        expect(trace.writes == 0 && trace.acquisitions == 0, "Rejected identity changes precede sandbox access and system writes")
        expect(try Data(contentsOf: device) == bytes, "Rejected identity changes preserve device bytes")
        expect(try await store.backups().count == 1, "Rejected identity changes do not create backups")
        expect(!fm.fileExists(atPath: backups.appendingPathComponent("OriginalValues.plist").path), "Rejected identity changes do not poison the journal")

        var unrelated = initial.document
        // "setting" is not a staged key (Stage 5 §3.4 allowlist
        // gate), so the unrelated edit uses the staged region code.
        unrelated.set("LL", for: GestaltKeys.regionCode)
        do {
            _ = try await store.commit(unrelated, expected: initial)
        } catch is GestaltFailure {
            throw error
        } catch {
            // Diagnostic (Stage 9 fix9): the commit path only throws
            // GestaltFailure, so a different error here names the site
            // instead of failing opaquely.
            throw Failure(message: "Unrelated staged edit threw unexpected error: \(error)")
        }
        let reopened = try await store.loadDevice()
        expect(reopened.document.extra[GestaltKeys.regionCode] as? String == "LL", "Other staged edits still commit and reopen with their original identity")
        expect(trace.writes == 1, "Only the permitted edit reaches the writer")

        let local = try await store.loadLocal(data: bytes, name: "local.plist")
        var localEdit = local.document
        for key in identifiers.keys { localEdit.set(nil, for: key) }
        let savedLocal: DocumentSnapshot
        do {
            savedLocal = try await store.commit(localEdit, expected: local)
        } catch is GestaltFailure {
            throw error
        } catch {
            // Diagnostic (Stage 9 fix9): see the unrelated edit above.
            throw Failure(message: "Local identity removal threw unexpected error: \(error)")
        }
        expect(savedLocal.document.extra.isEmpty && trace.writes == 1, "Local documents remain freely editable")

        let emptyDevice = directory.appendingPathComponent("missing-identifiers.plist")
        let emptyBytes = try PropertyListSerialization.data(fromPropertyList: ["CacheExtra": [String: Any]()], format: .binary, options: 0)
        try emptyBytes.write(to: emptyDevice)
        let emptyStore = GestaltFileStore(deviceURL: emptyDevice, backupDirectory: directory.appendingPathComponent("missing-backups"),
                                          deviceID: "missing-fixture", acquire: { 1 }, release: { _ in })
        let empty = try await emptyStore.loadDevice()
        for (key, value) in identifiers {
            var added = empty.document
            added.set(value, for: key)
            do {
                _ = try await emptyStore.commit(added, expected: empty)
                throw Failure(message: "A previously absent system identity field was added: " + key)
            } catch is GestaltFailure {}
            catch {
                // Diagnostic (Stage 9 fix9): see the identity loop above.
                throw Failure(message: "Adding absent identity field \(key) threw unexpected error: \(error)")
            }
        }
        expect(try Data(contentsOf: emptyDevice) == emptyBytes, "Absent identity fields remain absent on the device")
    }
}
