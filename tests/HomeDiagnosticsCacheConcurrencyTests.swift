// SPDX-License-Identifier: GPL-3.0-only
//
// HomeDiagnosticsCacheConcurrencyTests.swift — concurrency safety
// tests for the shared home-diagnostics cache (Phase H, gap 3).
//
// The cache is @MainActor (it owns @Published state) and does its
// heavy work in a `Task.detached`; the tests prove, with the REAL
// cache and the REAL fixtures (no mock), that:
//   - Concurrent refreshes with identical inputs converge on one
//     deterministic final state (no crash, no stuck `isComputing`).
//   - Concurrent readers sampling the published report while
//     refreshes alternate between two snapshots never observe a
//     torn value: every sample is nil, the first snapshot's whole
//     report, or the second snapshot's whole report.
//   - A refresh triggered from a background task still publishes
//     on the main actor (the values arrive and are readable).
//
// Determinism: no sleeps, no timing assertions. Readers sample a
// bounded number of times with `Task.yield()` between samples;
// refreshes are issued a bounded number of times; the only
// assertions are membership in the set of legitimate whole
// values and the final converged state. Tests await refresh completion.
import XCTest

@testable import GestaltX

@MainActor
final class HomeDiagnosticsCacheConcurrencyTests: XCTestCase {

    // MARK: - Fixtures (same fixtures as HomeDiagnosticsCacheTests)

    private func snapshotA() throws -> DocumentSnapshot {
        let document = try CoreModuleFixtures.document(
            extra: [
                GestaltKeys.productType: "iPhone18,1",
                GestaltKeys.regionCode: "LL",
            ],
            greenTea: false,
            notGreenTea: true,
            wapi: false
        )
        return CoreModuleFixtures.snapshot(document: document)
    }

    private func snapshotB() throws -> DocumentSnapshot {
        CoreModuleFixtures.snapshot(document: try CoreModuleFixtures.document())
    }

    // MARK: - Helpers

    private func refreshAndWait(
        _ cache: HomeDiagnosticsCache,
        snapshot: DocumentSnapshot?,
        working: GestaltDocument?,
        backups: [BackupRecord]
    ) async {
        await cache.refresh(snapshot: snapshot, working: working, backups: backups).value
    }

    private func hasSameDiagnostics(_ report: LilaDeviceReport, as reference: LilaDeviceReport) -> Bool {
        let recommendation = report.chinaUnlockRecommendation
        let referenceRecommendation = reference.chinaUnlockRecommendation
        // A fresh computation assigns new creation metadata to the same recommendation.
        let normalized = LilaRecommendation(
            id: referenceRecommendation.id, createdAt: referenceRecommendation.createdAt,
            deviceID: recommendation.deviceID, productType: recommendation.productType,
            steps: recommendation.steps, blockers: recommendation.blockers,
            requiresRestart: recommendation.requiresRestart)
        return LilaDeviceReport(profile: report.profile, evaluations: report.evaluations,
                                chinaUnlockRecommendation: normalized) == reference
    }

    // MARK: - Concurrent refreshes converge

    func testConcurrentRefreshesWithSameInputsConverge() async throws {
        let cache = HomeDiagnosticsCache()
        let snapshot = try snapshotA()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    await cache.refresh(snapshot: snapshot, working: snapshot.document, backups: []).value
                }
            }
        }
        XCTAssertFalse(cache.isComputing)
        XCTAssertNotNil(cache.deviceReport)
        XCTAssertEqual(cache.deviceReport?.profile.regionCode.value, "LL")
        XCTAssertTrue(cache.backupVerifications.isEmpty)
        XCTAssertTrue(cache.stagedFeatureIDs.isEmpty)
    }

    // MARK: - Concurrent reads never observe a torn report

    func testConcurrentReadsNeverObserveATornReport() async throws {
        let cache = HomeDiagnosticsCache()
        let first = try snapshotA()
        let second = try snapshotB()

        // Establish the two whole values the cache may publish.
        await refreshAndWait(cache, snapshot: first, working: first.document, backups: [])
        let reportA = try XCTUnwrap(cache.deviceReport)
        await refreshAndWait(cache, snapshot: second, working: second.document, backups: [])
        let reportB = try XCTUnwrap(cache.deviceReport)
        XCTAssertNotEqual(reportA, reportB)

        await withTaskGroup(of: [LilaDeviceReport?].self) { group in
            for _ in 0..<8 {
                group.addTask {
                    var seen: [LilaDeviceReport?] = []
                    for _ in 0..<20 {
                        seen.append(await cache.deviceReport)
                        await Task.yield()
                    }
                    return seen
                }
            }
            // Alternate refreshes between the two snapshots while
            // the readers sample. The group body runs on the main
            // actor; each yield lets the refresh tasks apply.
            var latest: Task<Void, Never>?
            for _ in 0..<4 {
                cache.refresh(snapshot: first, working: first.document, backups: [])
                await Task.yield()
                latest = cache.refresh(snapshot: second, working: second.document, backups: [])
                await Task.yield()
            }
            for await seen in group {
                for report in seen {
                    if let report {
                        XCTAssertTrue(
                            hasSameDiagnostics(report, as: reportA) || hasSameDiagnostics(report, as: reportB),
                            "Reader observed a report that is neither snapshot's whole report")
                    }
                }
            }
            await latest?.value
        }
        XCTAssertFalse(cache.isComputing)
        XCTAssertNotNil(cache.deviceReport)
        XCTAssertEqual(cache.deviceReport?.profile.regionCode.value, "CH")
    }

    // MARK: - Refresh from a background task publishes on the main actor

    func testRefreshTriggeredFromBackgroundTaskPublishes() async throws {
        let cache = HomeDiagnosticsCache()
        let snapshot = try snapshotA()

        await Task.detached {
            await cache.refresh(snapshot: snapshot, working: snapshot.document, backups: []).value
        }.value
        XCTAssertFalse(cache.isComputing)
        XCTAssertNotNil(cache.deviceReport)
        XCTAssertEqual(cache.deviceReport?.profile.regionCode.value, "LL")
    }

    func testDeviceSwitchClearsPreviousDiagnosticsAndOnlyPublishesLatestRefresh() async throws {
        let cache = HomeDiagnosticsCache()
        let first = try snapshotA()
        let second = try snapshotB()
        await cache.refresh(snapshot: first, working: first.document, backups: []).value
        XCTAssertEqual(cache.deviceReport?.profile.regionCode.value, "LL")
        XCTAssertNotNil(cache.healthScore)
        XCTAssertNotNil(cache.currentFingerprint)

        let superseded = cache.refresh(snapshot: first, working: first.document, backups: [])
        let latest = cache.refresh(snapshot: second, working: second.document, backups: [])
        XCTAssertNil(cache.deviceReport)
        XCTAssertNil(cache.healthScore)
        XCTAssertNil(cache.currentFingerprint)
        XCTAssertTrue(cache.simulations.isEmpty)

        await latest.value
        await superseded.value
        XCTAssertTrue(superseded.isCancelled)
        XCTAssertEqual(cache.deviceReport?.profile.regionCode.value, "CH")
        XCTAssertEqual(cache.currentFingerprint?.regionCode, "CH")
        XCTAssertFalse(cache.isComputing)
    }

    func testCancelledRefreshClearsLoadingAndDoesNotPublish() async throws {
        let cache = HomeDiagnosticsCache()
        let snapshot = try snapshotA()
        let refresh = cache.refresh(snapshot: snapshot, working: snapshot.document, backups: [])
        refresh.cancel()
        await refresh.value

        XCTAssertTrue(refresh.isCancelled)
        XCTAssertNil(cache.deviceReport)
        XCTAssertNil(cache.currentFingerprint)
        XCTAssertFalse(cache.isComputing)
    }
}
