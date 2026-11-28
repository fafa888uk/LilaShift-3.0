// SPDX-License-Identifier: GPL-3.0-only
// Wiring tests (LilaShift 5.0.0, Wave 1 wiring): the Wave 1
// catalog pages and home diagnostics rows added by the wiring
// step, and the W4 non-pages that must NOT appear as pages.
//
// Existence and metadata only — no UI is run. Constructing a
// section's `detailContent` in a test builds the view value
// (a struct); it does not render it, and it needs no
// environment object at construction time (StructuredLogView
// reads its GestaltManager from the environment only when
// rendered, inside ContentView, which injects it).
import Foundation
import XCTest
@testable import GestaltX

final class WiringTests: XCTestCase {
    /// The five Wave 1 pages added by the wiring step: id, the
    /// catalog category the registration files assign, and the
    /// dashboard destination the page lives on.
    private var expectedPages: [(id: String, category: FeatureCatalogCategory, destination: DashboardV3Destination)] {
        [
            ("page.deviceDiagnostics", .deviceDiagnostics, .diagnostics),
            ("page.structuredLog", .deviceDiagnostics, .diagnostics),
            ("page.ipaAudit", .deviceDiagnostics, .diagnostics),
            ("page.networkProbe", .deviceDiagnostics, .diagnostics),
            ("page.fileBrowser", .advancedTools, .advanced),
        ]
    }

    /// The four Wave 1 home diagnostics sections added by the
    /// wiring step, in enum order.
    private var expectedSections: [HomeDiagnosticsSectionID] {
        [.deviceDiagnostics, .structuredLog, .ipaAudit, .networkProbe]
    }

    func testNewPageItemsExistWithCorrectCategoryAndDestination() {
        for expected in expectedPages {
            guard let item = FeatureCatalog.pageItems.first(where: { $0.id == expected.id }) else {
                XCTFail("Missing Wave 1 page \(expected.id)")
                continue
            }
            XCTAssertEqual(item.kind, .page, "\(expected.id) must be a page, not a preset")
            XCTAssertEqual(item.category, expected.category, "\(expected.id) has the wrong category")
            XCTAssertEqual(item.destination, expected.destination, "\(expected.id) has the wrong destination")
            XCTAssertFalse(item.chineseName.isEmpty, "Missing title for \(expected.id)")
            XCTAssertFalse(item.chineseDescription.isEmpty, "Missing subtitle for \(expected.id)")
            XCTAssertFalse(item.symbol.isEmpty, "Missing symbol for \(expected.id)")
            XCTAssertNil(item.riskLevel, "Page item \(expected.id) must not carry a risk level")
        }
        XCTAssertEqual(FeatureCatalog.pageItems.count, 25)
    }

    func testNewPageIDsAreUniqueAcrossTheCatalog() {
        let ids = FeatureCatalog.allItems.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Catalog ids must be unique")
        for expected in expectedPages {
            XCTAssertEqual(ids.filter { $0 == expected.id }.count, 1, "\(expected.id) must appear exactly once")
        }
    }

    func testHomeDiagnosticsHasFourNewSectionsAtTheEnd() {
        XCTAssertEqual(HomeDiagnosticsSectionID.allCases.count, 15)
        XCTAssertEqual(HomeDiagnosticsSectionID.defaultOrder, HomeDiagnosticsSectionID.allCases)
        let cases = HomeDiagnosticsSectionID.allCases
        XCTAssertEqual(
            Array(cases.suffix(expectedSections.count)), expectedSections,
            "The Wave 1 sections must be the last cases, so stored section orders never shift")
        for section in expectedSections {
            XCTAssertFalse(section.title.isEmpty, "Missing title for \(section)")
            XCTAssertFalse(section.subtitle.isEmpty, "Missing subtitle for \(section)")
            XCTAssertFalse(section.symbol.isEmpty, "Missing symbol for \(section)")
        }
    }

    func testHomeDiagnosticsNewSectionsAreVisibleByDefault() {
        let visible = HomeDiagnosticsSectionID.orderedVisibleSections(.defaults)
        for section in expectedSections {
            XCTAssertTrue(
                visible.contains(section),
                "New section \(section) must be visible by default (defaultOrder = allCases appends it)")
        }
    }

    func testHomeDiagnosticsNewSectionsDetailContentConstructs() {
        // Construction is the check: if a view type or its init
        // were wrong, this would not compile. Nothing is rendered.
        // No cast to the leaf view type is possible here: the
        // `@ViewBuilder` switch returns an opaque `some View`
        // whose underlying type is a nested conditional, not the
        // leaf view — so the branch is pinned by compilation, not
        // by a runtime cast.
        for section in expectedSections {
            let content = section.detailContent
            _ = content
        }
    }

    func testW4RegistrationIDsAreNotPages() {
        let pageIDs = Set(FeatureCatalog.pageItems.map(\.id))
        for feature in W4Registration.features {
            XCTAssertFalse(
                pageIDs.contains(feature.id),
                "W4 feature \(feature.id) is an MG field editor enhancement, not a page")
        }
        let catalogIDs = Set(FeatureCatalog.allItems.map(\.id))
        for feature in W4Registration.features {
            XCTAssertFalse(
                catalogIDs.contains(feature.id),
                "W4 feature \(feature.id) must not appear in the catalog at all")
        }
    }
}
