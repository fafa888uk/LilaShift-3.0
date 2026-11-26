import Foundation
import XCTest
@testable import GestaltX

/// Offline tests for the proxy rule generator (A9, Erosion-CN
/// AppGroupHubView): the generated Surge module and Stash override
/// must keep the China Siri gateway on DIRECT, route Apple
/// Intelligence / PCC / ChatGPT domains to the policy group, and
/// sanitise an empty policy name. Pure string tests, no device.
final class ProxyRuleGeneratorTests: XCTestCase {
    func testSurgeModuleKeepsSiriGatewayDirect() {
        let content = ProxyRuleGenerator.buildSGModuleContent(policy: "PROXY")
        XCTAssertTrue(content.contains("DOMAIN-SUFFIX,guzzoni.apple.com,DIRECT"))
        XCTAssertTrue(content.contains("DOMAIN-SUFFIX,siri.apple.com,DIRECT"))
        XCTAssertTrue(content.contains("DOMAIN,dejavu.apple.com,DIRECT"))
        XCTAssertTrue(content.contains("DOMAIN,sequoia.apple.com,DIRECT"))
        XCTAssertTrue(content.contains("DOMAIN-SUFFIX,smoot.apple.com,DIRECT"))
    }

    func testSurgeModuleRoutesIntelligenceToPolicy() {
        let content = ProxyRuleGenerator.buildSGModuleContent(policy: "US-Node")
        XCTAssertTrue(content.contains("DOMAIN,gspe1-ssl.ls.apple.com,US-Node"))
        XCTAssertTrue(content.contains("DOMAIN-SUFFIX,issuer.apple.com,US-Node"))
        XCTAssertTrue(content.contains("DOMAIN,mask-api.icloud.com,US-Node"))
        XCTAssertTrue(content.contains("DOMAIN-SUFFIX,openai.com,US-Node"))
        XCTAssertTrue(content.contains("DOMAIN-SUFFIX,chatgpt.com,US-Node"))
        XCTAssertTrue(content.contains("DOMAIN,lens.google.com,US-Node"))
    }

    func testSurgeModuleHasRealIPSection() {
        let content = ProxyRuleGenerator.buildSGModuleContent(policy: "PROXY")
        XCTAssertTrue(content.contains("always-real-ip"))
        XCTAssertTrue(content.contains("skip-proxy"))
        XCTAssertTrue(content.contains("#!name="))
    }

    func testStashOverrideKeepsSiriGatewayDirect() {
        let content = ProxyRuleGenerator.buildStashOverrideContent(policy: "PROXY")
        XCTAssertTrue(content.contains("DOMAIN-SUFFIX,guzzoni.apple.com,DIRECT"))
        XCTAssertTrue(content.contains("DOMAIN-SUFFIX,siri.apple.com,DIRECT"))
        XCTAssertTrue(content.contains("fake-ip-filter"))
    }

    func testStashOverrideRoutesIntelligenceToPolicy() {
        let content = ProxyRuleGenerator.buildStashOverrideContent(policy: "US-Node")
        XCTAssertTrue(content.contains("DOMAIN,gspe1-ssl.ls.apple.com,US-Node"))
        XCTAssertTrue(content.contains("DOMAIN-SUFFIX,openai.com,US-Node"))
        XCTAssertTrue(content.contains("DOMAIN-SUFFIX,claude.ai,US-Node"))
    }

    func testEmptyPolicyFallsBackToProxy() {
        XCTAssertEqual(ProxyRuleGenerator.sanitizedPolicy(""), "PROXY")
        XCTAssertEqual(ProxyRuleGenerator.sanitizedPolicy("   "), "PROXY")
        XCTAssertEqual(ProxyRuleGenerator.sanitizedPolicy("US-Node"), "US-Node")
        XCTAssertEqual(ProxyRuleGenerator.sanitizedPolicy("  US-Node  "), "US-Node")
    }

    func testContentDispatchesByFormat() {
        let surge = ProxyRuleGenerator.content(for: .surgeModule, policy: "PROXY")
        XCTAssertTrue(surge.contains("[Rule]"))
        let stash = ProxyRuleGenerator.content(for: .stashOverride, policy: "PROXY")
        XCTAssertTrue(stash.contains("rules:"))
        XCTAssertFalse(surge.contains("rules:"))
    }

    func testFileNames() {
        XCTAssertEqual(ProxyRuleFormat.surgeModule.fileName, "LilaShift-AppleIntelligence-CN.sgmodule")
        XCTAssertEqual(ProxyRuleFormat.stashOverride.fileName, "LilaShift-AppleIntelligence-CN.stoverride")
    }
}
