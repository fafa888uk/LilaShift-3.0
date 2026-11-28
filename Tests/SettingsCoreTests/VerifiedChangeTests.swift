import XCTest
@testable import SettingsCore

final class VerifiedChangeTests: XCTestCase {
    func testWriteAndRestoreBothReadBack() {
        var change = VerifiedChange<Int>()
        var value = 40
        var reads = 0
        let read: () -> Int? = { reads += 1; return value }
        let write: (Int) -> Void = { value = $0 }
        XCTAssertEqual(change.apply(70, read: read, write: write, equals: ==), .applied)
        XCTAssertEqual(value, 70)
        XCTAssertTrue(change.canRestore)
        XCTAssertEqual(change.restore(read: read, write: write, equals: ==), .restored)
        XCTAssertEqual(value, 40)
        XCTAssertFalse(change.canRestore)
        XCTAssertEqual(reads, 4)
    }

    func testRejectedWriteDoesNotReportSuccess() {
        var change = VerifiedChange<Int>()
        XCTAssertEqual(change.apply(70, read: { 40 }, write: { _ in }, equals: ==),
                       .writeRejectedAndOriginalRecovered)
        XCTAssertFalse(change.canRestore)
    }

    func testUnavailableReadingNeverWrites() {
        var change = VerifiedChange<Int>()
        XCTAssertEqual(change.apply(70, read: { nil }, write: { _ in XCTFail() }, equals: ==),
                       .unavailable)
    }

    func testExternalChangeIsNotOverwritten() {
        var change = VerifiedChange<Int>()
        var value = 40
        XCTAssertEqual(change.apply(70, read: { value }, write: { value = $0 }, equals: ==), .applied)
        value = 55
        XCTAssertEqual(change.restore(read: { value }, write: { _ in XCTFail() }, equals: ==),
                       .externallyChanged)
        XCTAssertEqual(value, 55)
        XCTAssertTrue(change.canRestore)
        change.discard()
        XCTAssertFalse(change.canRestore)
    }

    func testRejectedRestoreRemainsRetryable() {
        var change = VerifiedChange<Int>()
        var value = 40
        XCTAssertEqual(change.apply(70, read: { value }, write: { value = $0 }, equals: ==), .applied)
        XCTAssertEqual(change.restore(read: { value }, write: { _ in }, equals: ==), .restoreUnverified)
        XCTAssertTrue(change.canRestore)
        XCTAssertEqual(change.restore(read: { value }, write: { value = $0 }, equals: ==), .restored)
    }

    func testPendingTransactionCannotBeOverwritten() {
        var change = VerifiedChange<Int>()
        var value = 40
        XCTAssertEqual(change.apply(70, read: { value }, write: { value = $0 }, equals: ==), .applied)
        XCTAssertEqual(change.apply(60, read: { value }, write: { _ in XCTFail() }, equals: ==), .busy)
        value = 40
        XCTAssertEqual(change.restore(read: { value }, write: { _ in XCTFail() }, equals: ==), .restored)
    }

    func testUnchangedValueDoesNotWrite() {
        var change = VerifiedChange<Int>()
        XCTAssertEqual(change.apply(40, read: { 40 }, write: { _ in XCTFail() }, equals: ==), .unchanged)
    }
}
