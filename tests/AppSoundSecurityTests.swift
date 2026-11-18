// SPDX-License-Identifier: GPL-3.0-only
// App Audio Library security tests (Stage 13).
//
// The store's security properties, asserted as guarantees rather
// than as side effects of the happy path: the version-sentinel gate
// the Tools-page tile uses, the path allowlist, the sibling-`.bak`
// backup verification, and stale-pinning refusal. The behavioural
// scenarios here intentionally overlap `AppSoundTests` — that file
// proves the flows work; this file names the properties that must
// never regress.
import Foundation
import XCTest
@testable import GestaltX

final class AppSoundSecurityTests: XCTestCase {
    let fm = FileManager.default

    func testSentinelGateBlocksOnBlockedAndUnknownBuilds() {
        // 27.3 beta 1 is the last supported build: the tile is enabled.
        XCTAssertNil(AppSoundAvailability.unavailableReason(forBuild: "24C5037i"),
                     "A supported build must not be gated")
        // 27.3 beta 2 blocked worse_query: the tile is disabled with guidance.
        XCTAssertNotNil(AppSoundAvailability.unavailableReason(forBuild: "24C5049d"),
                        "A blocked build must be gated")
        // Unknown builds are never assumed supported.
        XCTAssertNotNil(AppSoundAvailability.unavailableReason(forBuild: "not-a-build"),
                        "An unparsable build must be gated")
        XCTAssertNotNil(AppSoundAvailability.unavailableReason(forBuild: nil),
                        "An unreadable build must be gated")
    }

    func testPathAllowlistRejectsTraversalAndAbsolutePaths() {
        XCTAssertFalse(AppSoundDirectory.validPath("Library/../outside.wav"),
                       "A path escaping its directory must be rejected")
        XCTAssertFalse(AppSoundDirectory.validPath("/Library/Sounds/x.wav"),
                       "An absolute path must be rejected")
        XCTAssertFalse(AppSoundDirectory.validPath("Library/Sounds/.GestaltX-x.wav"),
                       "A path colliding with the temp prefix must be rejected")
        XCTAssertFalse(AppSoundDirectory.validPath("Library/Sounds/x.txt"),
                       "A non-audio extension must be rejected")
        XCTAssertTrue(AppSoundDirectory.validPath("Library/Sounds/message.wav"))
        XCTAssertTrue(AppSoundDirectory.validPath("Library/Sound/notification.mp3"))
        XCTAssertTrue(AppSoundDirectory.validPath("Sounds/message.wav"))
    }

    func testAudioStoragePaths() {
        XCTAssertTrue(AppDirectories.audioStorage.path.hasSuffix("GestaltX/Audio"),
                      "Audio backups live under GestaltX/Audio")
        XCTAssertTrue(AppDirectories.audioCatalogStorage.path.hasSuffix("GestaltX/NotificationSoundCatalog-v2"),
                      "The audio catalog lives under GestaltX/NotificationSoundCatalog-v2")
        XCTAssertTrue(AppDirectories.audioStorage.path.hasPrefix(AppDirectories.applicationSupport.path),
                      "Audio storage is inside Application Support")
    }

    /// Minimal container with a single notification sound, for the
    /// two behavioural security properties below. Both sounds are
    /// real WAVs with identical format, sample rate and channel
    /// count (so `apply` reaches the pinning check instead of
    /// failing the format check first); they differ only in tone.
    struct Fixture {
        let root: URL
        let container: URL
        let target: URL
        let original: Data
        let input: Data
        let imported: URL
        let app: LaunchArtworkApp
        let store: AppSoundStore
    }

    func wav(rate: Int = 16000, channels: Int = 1, frequency: Double = 440) -> Data {
        let frames = rate / 4, bytes = frames * channels * 2
        var data = Data()
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func u32(_ value: Int) { var n = UInt32(value).littleEndian; withUnsafeBytes(of: &n) { data.append(contentsOf: $0) } }
        func u16(_ value: Int) { var n = UInt16(value).littleEndian; withUnsafeBytes(of: &n) { data.append(contentsOf: $0) } }
        text("RIFF"); u32(bytes + 36); text("WAVEfmt "); u32(16); u16(1); u16(channels)
        u32(rate); u32(rate * channels * 2); u16(channels * 2); u16(16); text("data"); u32(bytes)
        for frame in 0..<frames {
            var sample = Int16(sin(Double(frame) * frequency * 2 * .pi / Double(rate)) * 15000).littleEndian
            for _ in 0..<channels { withUnsafeBytes(of: &sample) { data.append(contentsOf: $0) } }
        }
        return data
    }

    func makeFixture() throws -> Fixture {
        let root = fm.temporaryDirectory.appendingPathComponent("GX-SoundSecurity-\(UUID().uuidString)", isDirectory: true)
        let container = root.appendingPathComponent("App", isDirectory: true)
        let sounds = container.appendingPathComponent("Library/Sounds", isDirectory: true)
        try fm.createDirectory(at: sounds, withIntermediateDirectories: true)
        let target = sounds.appendingPathComponent("message.wav")
        let original = wav(), input = wav(frequency: 880)
        try original.write(to: target)
        let imported = root.appendingPathComponent("import.wav")
        try input.write(to: imported)
        let app = LaunchArtworkApp(id: "test.audio", name: "Test")
        let store = AppSoundStore(storage: root.appendingPathComponent("GestaltX", isDirectory: true),
                                  device: "install1", resolver: { _ in container })
        return Fixture(root: root, container: container, target: target, original: original,
                       input: input, imported: imported, app: app, store: store)
    }

    func testStalePinningRefusesToOverwriteAppChangedAudio() async throws {
        let fixture = try makeFixture()
        defer { try? fm.removeItem(at: fixture.root) }
        // Pin the current bytes, then let the app change the file
        // behind our back; the apply must be refused and the app's
        // new bytes must survive untouched.
        let scan = try await fixture.store.scan(fixture.app)
        let selection = try await fixture.store.select(scan.files[0], app: fixture.app)
        try fixture.input.write(to: fixture.target, options: .atomic)
        do {
            try await fixture.store.apply(fixture.input, selection: selection, app: fixture.app)
            XCTFail("A stale selection overwrote app-generated data")
        } catch {
            // Refusal is the correct outcome.
        }
        XCTAssertEqual(try Data(contentsOf: fixture.target), fixture.input,
                       "A stale selection overwrote app-generated data")
    }

    func testForeignBackupIsNeverAdopted() async throws {
        let fixture = try makeFixture()
        defer { try? fm.removeItem(at: fixture.root) }
        // A .bak whose bytes do not match the pinned current bytes is
        // foreign: selecting the sound must fail, and the foreign
        // .bak must be left exactly as it was.
        try fixture.input.write(to: fixture.target.appendingPathExtension("bak"))
        let scan = try await fixture.store.scan(fixture.app)
        do {
            _ = try await fixture.store.select(scan.files[0], app: fixture.app)
            XCTFail("A foreign .bak was adopted as the original")
        } catch {
            // Refusal is the correct outcome.
        }
        XCTAssertEqual(try Data(contentsOf: fixture.target.appendingPathExtension("bak")), fixture.input,
                       "A foreign .bak was overwritten")
    }
}
