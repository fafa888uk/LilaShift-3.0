// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Observations entered by the user after checking Settings on this device.
struct SiriSettingsObservation: Codable, Equatable {
    var appleAccountRegion = ""
    var siriLanguage = ""
    var traditionalSiriEnabled: Bool?
    var appleIntelligenceEnabled: Bool?
    var betaEntry: Bool?
    var betaEnabled: Bool?
    var joinedWaitlist: Bool?
    var voiceConfigured: Bool?
    var modelDownloaded: Bool?

    var confirmedRegion: String? {
        let region = appleAccountRegion.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return Locale.Region.isoRegions.contains { $0.identifier == region } ? region : nil
    }

    var confirmedSiriLanguage: String? {
        let language = siriLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        return language.isEmpty ? nil : language
    }
}

struct SiriBetaStatus {
    let nativeHardware: Bool
    let osVersion: String?
    let deviceLanguage: String?
    let settings: SiriSettingsObservation

    enum Outcome: Equatable {
        case unsupportedHardware, unsupportedOS, unsupportedRegion, unsupportedLanguage
        case pendingConfirmation, entryUnavailable, waitlisted, setupPending, readyInSettings

        var title: String {
            switch self {
            case .unsupportedHardware: persistenceText("Siri AI Beta requires supported hardware")
            case .unsupportedOS: persistenceText("Siri AI Beta requires iOS 27 or later")
            case .unsupportedRegion: persistenceText("Siri AI Beta is unavailable in the confirmed account region")
            case .unsupportedLanguage: persistenceText("Siri AI Beta requires English for the device and Siri")
            case .pendingConfirmation: persistenceText("Pending user confirmation")
            case .entryUnavailable: persistenceText("Beta entry is absent in Settings")
            case .waitlisted: persistenceText("Waiting for access according to Settings")
            case .setupPending: persistenceText("Siri AI Beta setup pending")
            case .readyInSettings: persistenceText("Siri AI Beta setup reported complete in Settings")
            }
        }
    }

    var outcome: Outcome {
        if !nativeHardware { return .unsupportedHardware }
        if let major = osVersion?.split(separator: ".").first.flatMap({ Int($0) }), major < 27 {
            return .unsupportedOS
        }
        if let region = settings.confirmedRegion, Self.restrictedAccountRegions.contains(region) {
            return .unsupportedRegion
        }
        if let deviceLanguage, !Self.isEnglish(deviceLanguage) { return .unsupportedLanguage }
        if let siriLanguage = settings.confirmedSiriLanguage, !Self.isEnglish(siriLanguage) {
            return .unsupportedLanguage
        }
        guard osVersion != nil, deviceLanguage != nil, settings.confirmedRegion != nil,
              settings.confirmedSiriLanguage != nil, let entry = settings.betaEntry
        else { return .pendingConfirmation }
        if !entry { return .entryUnavailable }
        if settings.joinedWaitlist == true && settings.betaEnabled != true { return .waitlisted }
        if settings.appleIntelligenceEnabled == true, settings.betaEnabled == true,
           settings.voiceConfigured == true, settings.modelDownloaded == true { return .readyInSettings }
        return .setupPending
    }

    private static func isEnglish(_ value: String) -> Bool {
        Locale.Language(identifier: value).languageCode?.identifier == "en"
    }

    // Apple Support 127893, iOS scope. Actual entry/access remains a Settings observation.
    private static let restrictedAccountRegions: Set<String> = [
        "CN", "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU",
        "IE", "IT", "LV", "LT", "LU", "MT", "NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE"
    ]
}
