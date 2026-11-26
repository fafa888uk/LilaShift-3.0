import Foundation
import XCTest
@testable import GestaltX

/// Offline tests for the supervision audit (A6, Erosion-CN
/// ConfigView): the fake-supervision detector must recognise a
/// residue file (only IsSupervised + OrganizationName) and must
/// never classify a genuine MDM enrollment as fake. No device is
/// needed: the pure `isGenuineMDMCloudConfiguration` predicate is
/// tested directly.
final class SupervisionAuditTests: XCTestCase {
    private func dict(_ pairs: [String: Any]) -> NSDictionary {
        NSDictionary(dictionary: pairs)
    }

    func testFakeResidueIsNotGenuineMDM() {
        XCTAssertFalse(SupervisionAudit.isGenuineMDMCloudConfiguration(dict([
            "IsSupervised": true,
            "OrganizationName": "Test Org",
        ])))
    }

    func testEmptyConfigurationIsNotGenuineMDM() {
        XCTAssertFalse(SupervisionAudit.isGenuineMDMCloudConfiguration(dict([:])))
    }

    func testSupervisedOnlyIsNotGenuineMDM() {
        XCTAssertFalse(SupervisionAudit.isGenuineMDMCloudConfiguration(dict(["IsSupervised": true])))
    }

    func testConfigurationURLMakesItGenuineMDM() {
        XCTAssertTrue(SupervisionAudit.isGenuineMDMCloudConfiguration(dict([
            "IsSupervised": true,
            "OrganizationName": "Test Org",
            "ConfigurationURL": "https://mdm.example.com/enroll",
        ])))
    }

    func testAnchorCertificatesMakeItGenuineMDM() {
        XCTAssertTrue(SupervisionAudit.isGenuineMDMCloudConfiguration(dict([
            "IsSupervised": true,
            "AnchorCertificates": [Data([1, 2, 3])],
        ])))
    }

    func testAnyExtraKeyMakesItGenuineMDM() {
        // Fail-closed: an unknown key means the file is not the
        // known fake residue shape, so it must never be deleted.
        XCTAssertTrue(SupervisionAudit.isGenuineMDMCloudConfiguration(dict([
            "IsSupervised": true,
            "OrganizationName": "Test Org",
            "SomeFutureKey": "value",
        ])))
    }

    func testConfigurationSourceMakesItGenuineMDM() {
        XCTAssertTrue(SupervisionAudit.isGenuineMDMCloudConfiguration(dict([
            "IsSupervised": true,
            "ConfigurationSource": "MDM",
        ])))
    }

    func testSupervisorHostCertificatesMakeItGenuineMDM() {
        XCTAssertTrue(SupervisionAudit.isGenuineMDMCloudConfiguration(dict([
            "IsSupervised": true,
            "SupervisorHostCertificates": [Data([4, 5, 6])],
        ])))
    }

    func testPostSetupProfileMakesItGenuineMDM() {
        XCTAssertTrue(SupervisionAudit.isGenuineMDMCloudConfiguration(dict([
            "IsSupervised": true,
            "PostSetupProfileWasInstalled": true,
        ])))
    }
}
