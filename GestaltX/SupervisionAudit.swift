// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Fake-supervision residue audit and cleanup (A6).
/// The mechanism is Erosion-CN's "伪监管残留死锁体检" (Kianuni,
/// GPL-3.0), reimplemented for LilaShift's access helper and storage.
/// A third-party tool can write a `CloudConfigurationDetails.plist`
/// that contains only `IsSupervised` and `OrganizationName` — no MDM
/// certificate chain — which makes the device look supervised without
/// a real MDM. After an OTA update that file can trigger a Setup
/// Assistant 403 activation deadlock (the Setup app loops on remote
/// management). This audit tells the three states apart and removes
/// ONLY the fake file:
///
/// * `.clean` — no CloudConfigurationDetails.plist exists.
/// * `.genuineMDM` — the file has a real MDM certificate chain or
///   other MDM keys; it is never deleted by this feature.
/// * `.fakeResidue` — the file has only IsSupervised/OrganizationName
///   and no MDM keys; deleting it is safe and preserves the lock
///   screen footnote and asset tag, which live in the separate
///   `SharedDeviceConfiguration.plist`.
///
/// Writing `IsSupervised=true` is permanently refused here: forcing
/// supervision on a personal retail device is what creates the
/// deadlock in the first place.
enum SupervisionAuditState: Equatable {
    case clean
    case genuineMDM(organization: String)
    case fakeResidue(organization: String)
}

enum SupervisionAudit {
    static let configurationProfilesDirectory =
        "/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles"
    static let cloudConfigurationFileName = "CloudConfigurationDetails.plist"
    static let sharedDeviceConfigurationFileName = "SharedDeviceConfiguration.plist"

    static var cloudConfigurationURL: URL {
        URL(fileURLWithPath: configurationProfilesDirectory)
            .appendingPathComponent(cloudConfigurationFileName)
    }

    static var sharedDeviceConfigurationURL: URL {
        URL(fileURLWithPath: configurationProfilesDirectory)
            .appendingPathComponent(sharedDeviceConfigurationFileName)
    }

    /// The MDM keys whose presence proves a configuration is a real
    /// enterprise/education MDM enrollment rather than a spoof.
    private static let genuineMDMKeys: Set<String> = [
        "ConfigurationSource",
        "PostSetupProfileWasInstalled",
        "AwaitDeviceConfigured",
        "CloudConfigurationUIComplete",
        "ConfigurationURL",
        "AnchorCertificates",
        "SupervisorHostCertificates",
    ]

    /// Keys a fake-supervision file is allowed to contain on its own.
    /// Anything else (or any genuine MDM key) makes it genuine.
    private static let fakeOnlyKeys: Set<String> = ["IsSupervised", "OrganizationName"]

    /// Classifies a CloudConfigurationDetails dictionary. Pure and
    /// unit-testable: a dictionary is genuine when it carries any MDM
    /// key, or any key beyond the fake-only pair; it is fake residue
    /// only when it is exactly the IsSupervised/OrganizationName pair.
    static func isGenuineMDMCloudConfiguration(_ dict: NSDictionary) -> Bool {
        for key in genuineMDMKeys where dict[key] != nil {
            return true
        }
        let allKeys = Set(dict.allKeys.compactMap { $0 as? String })
        return !allKeys.subtracting(fakeOnlyKeys).isEmpty
    }

    /// Reads the current CloudConfigurationDetails.plist (if any) and
    /// classifies it. Grants container access first; returns `.clean`
    /// when the file does not exist or cannot be read.
    static func audit() -> SupervisionAuditState {
        let fm = FileManager.default
        _ = ContainerAccess.grantAccess(path: configurationProfilesDirectory, requireWrite: false)
        guard fm.fileExists(atPath: cloudConfigurationURL.path),
              let dict = NSDictionary(contentsOf: cloudConfigurationURL) else {
            return .clean
        }
        let organization = dict["OrganizationName"] as? String ?? ""
        if isGenuineMDMCloudConfiguration(dict) {
            return .genuineMDM(organization: organization)
        }
        return .fakeResidue(organization: organization)
    }

    /// Deletes a fake-supervision CloudConfigurationDetails.plist,
    /// and only when the audit proves it is fake. No local backup
    /// is involved: the code removes only this residue file.
    /// Genuine MDM configurations are refused. The lock screen
    /// footnote and asset tag live in SharedDeviceConfiguration.plist
    /// and are untouched. Returns `true` when a fake file was removed.
    @discardableResult
    static func cleanFakeResidue() -> Bool {
        let fm = FileManager.default
        let grant = ContainerAccess.grantAccess(path: configurationProfilesDirectory, requireWrite: true)
        guard grant.granted else { return false }
        guard fm.fileExists(atPath: cloudConfigurationURL.path),
              let dict = NSDictionary(contentsOf: cloudConfigurationURL),
              !isGenuineMDMCloudConfiguration(dict) else {
            return false
        }
        do {
            try fm.removeItem(at: cloudConfigurationURL)
            return true
        } catch {
            return false
        }
    }
}
