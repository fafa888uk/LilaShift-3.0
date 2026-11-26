// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// DeviceSupportsSiriHub guard (A21).
///
/// The key is verified in Erosion-CN's `MGCacheLayout`
/// (`siriHubKey = "waGD2UTpntjbDXD1r3oALQ"`, Kianuni, GPL-3.0); it
/// is NOT present in upstream GestaltX 1.1.1 (no `SiriHub` reference
/// there). It names the on-device Siri Hub intent-routing slot: when
/// SiriHub routing is on, enabling Siri AI can hang at "Adding Siri
/// support" — Erosion-CN's inspector treats it as a gate conflict
/// ("检测到已开启 SiriHub 路由（会卡死“正在添加 Siri 支持内容”，
/// 可一键修复）") and its `isSiriHubConflictActive()` fires when the
/// CacheExtra key is 1, or the CacheData slot reads 1 against a
/// non-1 original.
///
/// LilaShift's guard reads the LIVE system answer
/// (`MGCopyAnswer`, via `LiveGestaltProbe`) — the system's current
/// routing state, whatever staged it. `liveValue == true` is a
/// conflict (the staging guard blocks until SiriHub is off);
/// `liveValue == nil` is unknown — the probe could not answer, and
/// the status is reported as unknown, never guessed. This mirrors
/// Erosion-CN, which also only conflicts on positive evidence
/// (its resolver falling through to `false` when unresolvable).
enum SiriHubGuard {
    /// DeviceSupportsSiriHub (Erosion-CN MGCacheLayout.siriHubKey).
    static let siriHubKey = "waGD2UTpntjbDXD1r3oALQ"

    enum Status: Equatable {
        /// The live probe could not answer — unknown, never guessed.
        case unknown
        /// SiriHub routing is off.
        case clear
        /// SiriHub routing is on — Siri AI enablement may hang.
        case conflict
    }

    /// Classifies a live probe value. Pure and unit-testable.
    static func status(liveValue: Bool?) -> Status {
        guard let liveValue else { return .unknown }
        return liveValue ? .conflict : .clear
    }

    /// The live on-device status (device-only; `nil` in the
    /// simulator reads as `.unknown`).
    static func liveStatus() -> Status {
        status(liveValue: LiveGestaltProbe.queryBool(siriHubKey))
    }

    /// User-facing reason for a conflict, for the staging guard and
    /// the diagnostics view.
    static let conflictReason = L("SiriHub routing is on. Enabling Siri AI while SiriHub is on can hang at “Adding Siri support”. Turn SiriHub off first, then try again.")

    /// User-facing note for an unknown probe.
    static let unknownNote = L("The live SiriHub probe could not answer on this device, so SiriHub routing is unverified. Staging is not blocked on an unverified probe.")
}
