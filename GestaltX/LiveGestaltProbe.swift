// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Read-only live MobileGestalt probe (MGCopyAnswer). Device-only; every
/// query returns `nil` in the simulator, and the checkup renders "live:
/// unknown" there — never a faked value. The probe returns system
/// capability answers, no user data.
enum LiveGestaltProbe {
    static func queryBool(_ key: String) -> Bool? {
        guard let raw = GXCopyLiveGestaltAnswer(key) else { return nil }
        switch ChangeValue.fromPlistValue(raw) {
        case .bool(let value): return value
        case .int(0): return false
        case .int(1): return true
        default: return nil
        }
    }

    static func queryString(_ key: String) -> String? {
        GXCopyLiveGestaltAnswer(key) as? String
    }

    static func query(_ key: String) -> PlistObservation? {
        GXCopyLiveGestaltAnswer(key).map(PlistObservation.init)
    }

    static func answers(for keys: Set<String>,
                        query: (String) -> PlistObservation? = LiveGestaltProbe.query) -> [String: PlistObservation] {
        var answers: [String: PlistObservation] = [:]
        for key in keys { answers[key] = query(key) }
        return answers
    }
}
