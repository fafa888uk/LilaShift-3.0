// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import XCTest
@testable import GestaltX

final class W7IntelligenceReportTests: XCTestCase {
    func testCountZeroDoesNotMeanMissing() throws {
        let summary = try W7IntelligenceReport.decode(Data(#"{"privateCloudComputeRequests":[]}"#.utf8))
        XCTAssertEqual(summary.privateCloudComputeRequests, 0)
        XCTAssertNil(summary.modelRequests)
    }

    func testOnlyCountsRecognizedTopLevelSections() throws {
        let data = Data(#"{"modelRequests":[{},{"nested":{"privateCloudComputeRequests":[{}]}}],"privateCloudComputeRequests":[{}]}"#.utf8)
        let summary = try W7IntelligenceReport.decode(data)
        XCTAssertEqual(summary.privateCloudComputeRequests, 1)
        XCTAssertEqual(summary.modelRequests, 2)
    }

    func testRejectsWrongShapeInsteadOfShowingSuccess() {
        XCTAssertThrowsError(try W7IntelligenceReport.decode(Data(#"{"privateCloudComputeRequests":[1]}"#.utf8))) { error in
            XCTAssertEqual(error as? W7IntelligenceReport.Failure, .invalidRequestList)
        }
        XCTAssertThrowsError(try W7IntelligenceReport.decode(Data(#"{"unrelated":[]}"#.utf8))) { error in
            XCTAssertEqual(error as? W7IntelligenceReport.Failure, .unrecognized)
        }
        XCTAssertThrowsError(try W7IntelligenceReport.decode(Data("{".utf8))) { error in
            XCTAssertEqual(error as? W7IntelligenceReport.Failure, .malformedJSON)
        }
    }

    func testReadRejectsLargeFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(repeating: 32, count: W7IntelligenceReport.maximumBytes + 1).write(to: url)
        XCTAssertThrowsError(try W7IntelligenceReport.read(url)) { error in
            XCTAssertEqual(error as? W7IntelligenceReport.Failure, .tooLarge)
        }
    }
}
