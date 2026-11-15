// SPDX-License-Identifier: GPL-3.0-only
import Foundation

@MainActor
extension GestaltManager {
    private func persistenceURL(_ name: String) -> URL {
        RestoreIntelligence.historyDirectory.appendingPathComponent(name + ".json")
    }

    private func loadPersistence<T: Decodable>(_ type: T.Type, name: String) -> T? {
        let url = persistenceURL(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do { return try JSONDecoder().decode(type, from: Data(contentsOf: url)) }
        catch {
            persistenceError = L("Saved persistence evidence could not be read.")
            return nil
        }
    }

    @discardableResult
    private func savePersistence<T: Encodable>(_ value: T, name: String) -> Bool {
        let url = persistenceURL(name)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
            return true
        } catch {
            persistenceError = L("Persistence evidence could not be saved.")
            return false
        }
    }

    func observeDeviceRead(_ snapshot: DocumentSnapshot) {
        let identity = SystemDeviceIdentitySource()
        let fingerprint = CacheFingerprint(snapshot: snapshot, osBuild: identity.osBuild)
        guard let productType = fingerprint.productType, productType == identity.productType else {
            persistenceError = L("The cache product type could not be matched to this device.")
            return
        }

        if deviceBaseline == nil {
            let stored = loadPersistence(DeviceBaseline.self, name: "device-baseline")
            if stored?.productType == productType { deviceBaseline = stored }
        }
        if siriSettings == SiriSettingsObservation(),
           let saved = loadPersistence(SiriSettingsObservation.self, name: "siri-settings-observations") {
            siriSettings = saved
        }
        if persistenceWrite == nil {
            persistenceWrite = loadPersistence(PersistenceWrite.self, name: "cache-write-evidence")
        }

        var keys = Set(ChinaUnlock.aiCapabilities.flatMap(\.keys))
        keys.formUnion([ChinaUnlock.onDeviceSiriKey, GestaltKeys.regionCode, GestaltKeys.modelNumber])
        if let write = persistenceWrite, write.fingerprint.productType == productType,
           let deviceID = RestoreIntelligence.installationDeviceID {
            keys.formUnion(write.records.filter {
                $0.layer == .cacheExtra && $0.deviceID == deviceID
            }.map(\.key))
        }
        let live = LiveGestaltProbe.answers(for: keys)
        let observation = DevicePersistenceRead(snapshot: snapshot, fingerprint: fingerprint,
                                                bootSession: BootSession.current(), readAt: Date(),
                                                liveProbeResults: live)
        devicePersistenceRead = observation
        refreshLiveProbe()
        guard deviceBaseline == nil else { return }
        let storage = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity
        let fields = ChinaUnlock.aiCapabilities.flatMap(\.keys) + [ChinaUnlock.onDeviceSiriKey]
        let original = Dictionary(uniqueKeysWithValues: fields.map { ($0, PlistObservation(snapshot.document.extra[$0])) })
        let baseline = DeviceBaseline(
            productType: productType, hardwareModel: LiveGestaltProbe.queryString("RegulatoryModelNumber")
                ?? snapshot.document.extra[GestaltKeys.modelNumber] as? String,
            osVersion: identity.osVersion, osBuild: identity.osBuild,
            deviceLanguage: Locale.preferredLanguages.first,
            siriLanguage: siriSettings.confirmedSiriLanguage, availableStorage: storage.map { Int64($0) },
            originalAIValues: original, liveProbeResults: live, fingerprint: fingerprint,
            bootSession: observation.bootSession, capturedAt: observation.readAt,
            audioIntelligenceSlot: DeviceCacheOptions.advAISlotValue(DeviceCacheOptions.audioIntelligenceKey,
                                                                      in: snapshot.document, using: fingerprint.layout),
            personalTranslatorSlot: DeviceCacheOptions.advAISlotValue(DeviceCacheOptions.personalTranslatorKey,
                                                                      in: snapshot.document, using: fingerprint.layout))
        deviceBaseline = baseline
        savePersistence(baseline, name: "device-baseline")
    }

    func observeVerifiedWrite(before: DocumentSnapshot, after: DocumentSnapshot, boot: BootSession?) {
        guard after.source == .device, !after.document.matches(before.document) else { return }
        devicePersistenceRead = nil
        refreshLiveProbe()
        let date = Date()
        let fingerprint = CacheFingerprint(snapshot: after, osBuild: SystemDeviceIdentitySource().osBuild)
        guard let deviceID = RestoreIntelligence.installationDeviceID else { return }
        let records = PostModificationAcceptance.records(before: before, after: after, deviceID: deviceID,
                                                           build: fingerprint.osBuild ?? "", date: date)
        let write = PersistenceWrite(fingerprint: fingerprint, bootSession: boot, writtenAt: date, records: records)
        persistenceWrite = write
        savePersistence(write, name: "cache-write-evidence")
    }

    func saveSiriSettings(_ settings: SiriSettingsObservation) {
        if savePersistence(settings, name: "siri-settings-observations") {
            siriSettings = settings
        }
    }

    func restartEvidence(manual: Bool = false) -> RestartEvidence {
        guard let read = devicePersistenceRead else { return .noFreshRead }
        if let write = matchingPersistenceWrite {
            return RestartEvidence.compare(before: write.bootSession, after: read.bootSession,
                                           referenceDate: write.writtenAt, readAt: read.readAt, manual: manual)
        }
        guard let baseline = deviceBaseline else { return .unknown }
        return RestartEvidence.compare(before: baseline.bootSession, after: read.bootSession,
                                       referenceDate: baseline.capturedAt, readAt: read.readAt, manual: manual)
    }

    var matchingPersistenceWrite: PersistenceWrite? {
        guard let write = persistenceWrite, let baseline = deviceBaseline,
              write.fingerprint.productType == baseline.productType,
              let deviceID = RestoreIntelligence.installationDeviceID,
              write.records.allSatisfy({ $0.deviceID == deviceID }) else { return nil }
        return write
    }

    func persistenceAcceptance(manual: Bool = false) -> AcceptanceReport {
        let write = matchingPersistenceWrite
        let read = devicePersistenceRead
        let sameBuild = write?.fingerprint.osBuild != nil && write?.fingerprint.osBuild == read?.fingerprint.osBuild
        let live = read?.liveProbeResults.compactMapValues { observation in
            observation.value.flatMap(ChangeValue.fromPlistValue)
        } ?? [:]
        return PostModificationAcceptance.accept(records: write?.records ?? [], current: read?.snapshot.document,
                                                 liveValues: live, restartEvidence: restartEvidence(manual: manual),
                                                 sameBuild: sameBuild || read == nil || write == nil)
    }

    func aiKeyDiagnostics(manual: Bool = false) -> [AIKeyDiagnostic] {
        guard let baseline = deviceBaseline, let read = devicePersistenceRead else { return [] }
        let restart = restartEvidence(manual: manual)
        let acceptance = persistenceAcceptance(manual: manual)
        return ChinaUnlock.aiCapabilities.flatMap { capability in
            capability.keys.map { key in
                let item = acceptance.items.first { $0.key == key && $0.layer == .cacheExtra }
                let target = previewTarget(for: key, in: capability, read: read) ?? item?.target
                let fileValue = PlistObservation(read.snapshot.document.extra[key])
                let slot = key == DeviceCacheOptions.audioIntelligenceKey || key == DeviceCacheOptions.personalTranslatorKey
                    ? DeviceCacheOptions.advAISlotValue(key, in: read.snapshot.document, using: read.fingerprint.layout) : nil
                let originalSlot = switch key {
                case DeviceCacheOptions.audioIntelligenceKey: baseline.audioIntelligenceSlot
                case DeviceCacheOptions.personalTranslatorKey: baseline.personalTranslatorSlot
                default: nil as Bool?
                }
                return AIKeyDiagnostic(
                    key: key, title: capability.title,
                    nativeHardware: DeviceAIEligibility.isNativeAppleIntelligence(productType: baseline.productType),
                    original: baseline.originalAIValues[key] ?? PlistObservation(nil), file: fileValue,
                    live: read.liveProbeResults[key], target: target,
                    postRestartFile: restart.hasPostRestartRead ? fileValue : nil,
                    postRestartLive: restart.hasPostRestartRead ? read.liveProbeResults[key] : nil,
                    status: item?.status ?? .unknown, observedScope: read.fingerprint.observedScope,
                    cacheDataSlot: slot, originalCacheDataSlot: originalSlot)
            }
        }
    }

    private func previewTarget(for key: String, in capability: Capability, read: DevicePersistenceRead) -> ChangeValue? {
        guard let preview, (choices[capability.id] ?? .keep) != .keep else { return nil }
        let value = ChangeValue.fromPlistValue(preview.extra[key])
        return value == ChangeValue.fromPlistValue(read.snapshot.document.extra[key]) ? nil : value
    }
}
