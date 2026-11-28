// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import SettingsCore

final class W11AppearanceModeTests: XCTestCase {
    func testDefaultKeepsExistingLightAppearance() {
        XCTAssertEqual(W11AppearanceMode.defaultMode, .light)
        XCTAssertEqual(W11AppearanceMode.stored("").preferredScheme, .light)
        XCTAssertEqual(W11AppearanceMode.stored("unknown-future-value").preferredScheme, .light)
    }

    func testExplicitModesResolveToSeparateSchemes() {
        XCTAssertEqual(W11AppearanceMode.stored("light").preferredScheme, .light)
        XCTAssertEqual(W11AppearanceMode.stored("dark").preferredScheme, .dark)
    }

    func testSystemModeClearsWindowOverride() {
        XCTAssertEqual(W11AppearanceMode.stored("system"), .system)
        XCTAssertNil(W11AppearanceMode.stored("system").preferredScheme)
    }

    func testStableStorageValuesRoundTrip() {
        XCTAssertEqual(Set(W11AppearanceMode.allCases.map(\.rawValue)), ["light", "dark", "system"])
        for mode in W11AppearanceMode.allCases {
            XCTAssertEqual(W11AppearanceMode.stored(mode.rawValue).id, mode)
        }
    }
}
