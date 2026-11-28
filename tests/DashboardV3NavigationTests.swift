// SPDX-License-Identifier: GPL-3.0-only
//
// DashboardV3NavigationTests.swift — navigation / reachability
// tests for the home and the unified feature catalog
// (Phase H, gap 7). A data test: no UI is needed, because
// reachability is a property of the section and catalog tables.
//
// What is proven here (and NOT already covered elsewhere):
//   - Every dashboard destination is reached from the home:
//     by a home section, or — Stage 14 — by one of the four
//     preset-group tiles in the common-features section. The
//     Siri AI Mode and eSIM & region pages have no home section
//     of their own (the home keeps its eight sections); they are
//     reached from their group tiles and from the catalog, so
//     they are not orphans — the test asserts exactly that.
//   - Every one of the 64 catalog items is reachable: it has a
//     non-empty id, names and symbol, and a destination that is
//     a real dashboard destination.
//   - Every dashboard destination is reached by at least one
//     catalog item.
//   - Every preset item's destination matches the staging-page
//     rule for its PresetEntry (`FeatureCatalog.destination`),
//     so the catalog never sends a preset to a page where it
//     cannot be staged.
//   - The home sections, the group tiles and the catalog agree
//     on the destinations: the sections reach six destinations,
//     the group tiles add the remaining two (Siri AI Mode,
//     eSIM & region), and together with the catalog they reach
//     exactly the eight dashboard destinations, so no
//     destination is reachable from one surface but missing
//     from the other.
import XCTest

@testable import GestaltX

final class DashboardV3NavigationTests: XCTestCase {

    /// The destinations the four preset-group tiles open from the
    /// home's common-features section (the no-favorites tiles, or
    /// the favorites the user chose — either way the tiles navigate
    /// by `FeatureCatalogItem.destination`).
    private var groupTileDestinations: Set<DashboardV3Destination> {
        Set(FeatureCatalog.presetItems
            .filter { PresetCatalog.entry(for: $0.id)?.kind == .group }
            .map(\.destination))
    }

    func testEveryDestinationIsReachedFromTheHome() {
        let sectionDestinations = Set(HomeSectionID.allCases.compactMap(\.destination))
        for destination in DashboardV3Destination.allCases {
            XCTAssertTrue(
                sectionDestinations.contains(destination)
                    || groupTileDestinations.contains(destination),
                "No home section or group tile opens \(destination.rawValue)")
        }
        XCTAssertEqual(
            groupTileDestinations,
            [.unlock, .aiOnly, .siriAIMode, .esimRegion],
            "The four preset-group tiles must open the four unlock-family pages")
    }

    func testEveryCatalogItemIsReachable() {
        XCTAssertEqual(FeatureCatalog.allItems.count, 64)
        for item in FeatureCatalog.allItems {
            XCTAssertFalse(item.id.isEmpty, "Catalog item has an empty id")
            XCTAssertFalse(item.chineseName.isEmpty, "Missing name for \(item.id)")
            XCTAssertFalse(item.englishTitle.isEmpty, "Missing English title for \(item.id)")
            XCTAssertFalse(item.chineseDescription.isEmpty, "Missing description for \(item.id)")
            XCTAssertFalse(item.symbol.isEmpty, "Missing symbol for \(item.id)")
            XCTAssertTrue(
                DashboardV3Destination.allCases.contains(item.destination),
                "\(item.id) points at an unknown destination")
            if item.kind == .preset {
                XCTAssertEqual(item.presetFeatureID, item.id)
                XCTAssertNotNil(item.riskLevel, "Preset item \(item.id) has no risk level")
            } else {
                XCTAssertNil(item.presetFeatureID)
                XCTAssertNil(item.riskLevel, "Page item \(item.id) must not carry a risk level")
            }
        }
        XCTAssertEqual(
            Set(FeatureCatalog.allItems.map(\.id)).count,
            FeatureCatalog.allItems.count,
            "Duplicate catalog ids would make one item unreachable")
    }

    func testEveryDestinationIsReachedByAtLeastOneCatalogItem() {
        for destination in DashboardV3Destination.allCases {
            let items = FeatureCatalog.allItems.filter { $0.destination == destination }
            XCTAssertFalse(
                items.isEmpty,
                "No catalog item opens \(destination.rawValue)")
        }
    }

    func testPresetItemDestinationsMatchTheStagingPageRule() {
        for item in FeatureCatalog.presetItems {
            guard let entry = PresetCatalog.entry(for: item.id) else {
                XCTFail("Preset item \(item.id) has no PresetEntry")
                continue
            }
            XCTAssertEqual(
                item.destination,
                FeatureCatalog.destination(for: entry),
                "\(item.id) points at \(item.destination.rawValue) but its entry stages on \(FeatureCatalog.destination(for: entry).rawValue)")
            XCTAssertEqual(
                item.category,
                FeatureCatalog.category(for: entry),
                "\(item.id) has category \(item.category.rawValue) but its entry maps to \(FeatureCatalog.category(for: entry).rawValue)")
        }
    }

    func testHomeSectionsGroupTilesAndCatalogAgreeOnDestinations() {
        let sectionDestinations = Set(HomeSectionID.allCases.compactMap(\.destination))
        let catalogDestinations = Set(FeatureCatalog.allItems.map(\.destination))
        // Six destinations have a home section; the other two
        // (Siri AI Mode, eSIM & region) are reached from the group
        // tiles instead — see testEveryDestinationIsReachedFromTheHome.
        XCTAssertEqual(
            sectionDestinations,
            [.unlock, .aiOnly, .diagnostics, .restore, .presets, .advanced])
        XCTAssertEqual(catalogDestinations, Set(DashboardV3Destination.allCases))
        XCTAssertEqual(sectionDestinations.union(groupTileDestinations), catalogDestinations)
    }
}
