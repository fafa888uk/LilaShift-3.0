// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 huamidev
import Foundation
import SwiftUI
import Combine

struct PlistImportOffer: Identifiable {
    let id = UUID()
    let data: Data
    let name: String
    let identity: DevicePlistIdentity?
    let sharedSource: (SharedPlistInbox, SharedPlistEntry)?
}

@MainActor
final class GestaltManager: ObservableObject {
    @Published private(set) var snapshot: DocumentSnapshot?
    @Published private(set) var working: GestaltDocument?
    @Published private(set) var isBusy = false
    /// True only while `connect()` is reading the device. Presentation
    /// state for the read-progress card; no read/write behavior depends
    /// on it.
    @Published private(set) var isReading = false
    @Published private(set) var status = "Connect to your device or open a plist."
    @Published private(set) var deviceAccessible = false
    @Published private(set) var backups: [BackupRecord] = []
    @Published private(set) var logs: [String] = []
    /// Structured operation events recorded this session (reads and
    /// backups only — see `OperationEventRecorder`). Observation
    /// only: recording never changes an operation's outcome.
    let operationEvents = OperationEventRecorder()
    /// When the last successful read happened, or `nil` when no read
    /// has happened yet. Read-path state only.
    @Published private(set) var lastReadAt: Date?
    @Published var message: String?
    @Published var needsRestart = false
    @Published var choices: [String: PresetChoice] = [:]
    @Published var regionID = "keep"
    @Published var regionCodeID = "keep"
    @Published var modelID = "keep"
    /// Region mode for China Unlock (default region-code-only).
    /// Persisted across launches; never reset by loading a document.
    /// The one-tap unlock stages the same items in either mode (10 on
    /// non-native hardware, 3 on native Apple Intelligence hardware);
    /// the mode only affects manual region presets and restoring an
    /// unlock applied by an older build.
    @Published var chinaUnlockRegionMode: ChinaUnlockRegionMode = .regionCodeOnly
    /// The user explicitly confirmed an unverified (warned) AI staging
    /// combination after reading its reason on the checkup card, by
    /// tapping Fix. In-memory only, never persisted: a fresh launch
    /// re-surfaces the warning. Reset whenever a new document is loaded.
    /// Only ever converts a `.warn` decision into `.allow` (see
    /// `AIStagingGuard`); a `.block` is never overridden by it.
    @Published var userConfirmedUnverifiedAICombination = false
    @Published var changesName = false
    @Published var modelName = ""
    @Published var subtype = 0
    @Published private(set) var wapiChoice: WAPIChoice = .keep
    @Published private(set) var cacheOptionChoice: CacheOptionChoice = .keep
    private let files: GestaltFileStore
    private var exploitLogObserver: NSObjectProtocol?

    init() {
        let defaults = UserDefaults.standard
        chinaUnlockRegionMode = ChinaUnlockRegionMode.stored
        let deviceID = defaults.string(forKey: "GestaltX.installationID") ?? UUID().uuidString
        defaults.set(deviceID, forKey: "GestaltX.installationID")
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GestaltX/Backups", isDirectory: true)
        files = GestaltFileStore(deviceURL: URL(fileURLWithPath: GestaltKeys.devicePath), backupDirectory: directory,
                                deviceID: deviceID, acquire: {
            #if targetEnvironment(simulator)
            throw GestaltFailure("Device access is unavailable in the Simulator. Open a plist to explore LilaShift.")
            #else
            let target = (GestaltKeys.devicePath as NSString).deletingLastPathComponent
            let signedGroups = GXEntitlementsReader.usableAppGroups()
            guard !signedGroups.isEmpty else {
                throw GestaltFailure("The signed app has no usable App Group. Enable its App Group capability and sign it again.")
            }
            // Re-signed certificates often carry several App Groups and only some of
            // them hold a usable container, so try each one instead of trusting one.
            var rejection: Int64 = -1
            for signedGroup in signedGroups {
                var handle = worse_query(target, signedGroup, false, false)
                if handle == -4, let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: signedGroup) {
                    // The exploit swaps Library/Caches for a symlink, so a container
                    // without Library fails until the directory exists.
                    try? FileManager.default.createDirectory(at: root.appendingPathComponent("Library/Caches"),
                                                             withIntermediateDirectories: true)
                    handle = worse_query(target, signedGroup, false, false)
                }
                if handle >= 0 { return handle }
                rejection = handle
            }
            if rejection == -1 {
                throw GestaltFailure("The signed app has no usable App Group. Enable its App Group capability and sign it again.")
            }
            throw GestaltFailure("MobileGestalt access was denied. Check the OS version and App Group signing.")
            #endif
        }, release: { worse_query_release($0) },
        expectedDeviceURL: URL(fileURLWithPath: GestaltKeys.devicePath),
        eventSink: { text in
            NotificationCenter.default.post(name: Notification.Name("GestaltX.worse_query.log"), object: nil,
                                            userInfo: ["message": text])
        })
        exploitLogObserver = NotificationCenter.default.addObserver(forName: Notification.Name("GestaltX.worse_query.log"), object: nil, queue: nil) { [weak self] notification in
            guard let text = notification.userInfo?["message"] as? String else { return }
            DispatchQueue.main.async { [weak self] in self?.log("[worse_query] " + text) }
        }
    }

    deinit { if let exploitLogObserver { NotificationCenter.default.removeObserver(exploitLogObserver) } }

    var changeKeys: [String] {
        guard let before = snapshot?.document, let after = preview else { return [] }
        return Self.changeKeys(before: before, after: after)
    }
    var cacheDataChanges: [CachedBooleanChange] {
        guard let original = snapshot?.document, let edited = preview else { return [] }
        return DeviceCacheOptions.changes(from: original, to: edited)
    }
    /// Full CacheData diff for the review sheet, including any changed
    /// byte outside the known slots.
    var cacheDataDiff: CacheDataDiff? {
        guard let original = snapshot?.document, let edited = preview else { return nil }
        return DeviceCacheOptions.diff(from: original, to: edited)
    }
    /// Pre-preview validation gate: the same `validateEdit` that `commit`
    /// enforces, run when the review sheet opens so a staged edit that
    /// fails validation is shown (and Apply disabled) before Apply is
    /// pressed. The commit-time check remains the enforcement point.
    var previewValidationError: String? {
        guard let snapshot, let preview else { return nil }
        do {
            try DeviceCacheOptions.validateEdit(from: snapshot.document, to: preview)
            return nil
        } catch {
            return error.localizedDescription
        }
    }
    /// One preview build per access: `changeKeys` and
    /// `cacheDataChanges` each build the preview on their own, so
    /// counting both here used to build it twice per body
    /// evaluation — and `changeCount` is read on many body paths
    /// (home, cards, review sheet). The count is identical; only
    /// the rebuild is removed.
    var changeCount: Int {
        guard let before = snapshot?.document, let after = preview else { return 0 }
        return Self.changeKeys(before: before, after: after).count
            + DeviceCacheOptions.changes(from: before, to: after).count
    }

    /// CacheExtra keys whose value differs between two documents.
    private static func changeKeys(before: GestaltDocument, after: GestaltDocument) -> [String] {
        let beforeExtra = before.extra
        let afterExtra = after.extra
        return Set(beforeExtra.keys).union(afterExtra.keys).filter { key in
            switch (beforeExtra[key], afterExtra[key]) {
            case (nil, nil): return false
            case (nil, _), (_, nil): return true
            case (let a?, let b?): return !GestaltDocument.valuesEqual(a, b)
            }
        }.sorted()
    }
    var hasDocument: Bool { snapshot != nil }
    var sourceIsDevice: Bool { snapshot?.source == .device }
    var artworkEditingError: GestaltFailure? {
        guard let working, !working.canEditArtwork else { return nil }
        return GestaltFailure("The artwork field is not a dictionary. Edit it in MG Control before using these presets.")
    }
    var displayedName: String {
        working?.artwork["ArtworkDeviceProductDescription"] as? String ?? working?.extra["Z/dqyWS6OZTRy10UcmUAhw"] as? String ?? UIDevice.current.model
    }
    var preview: GestaltDocument? {
        guard var doc = working, let snapshot else { return nil }
        for capability in Capability.all {
            capability.apply(choices[capability.id] ?? .keep, to: &doc, restoringFrom: snapshot)
        }
        if subtype != 0, doc.setArtwork(NSNumber(value: subtype), for: "ArtworkDeviceSubType") {
            doc.set(NSNumber(value: true), for: "YlEtTtHlNesRBMal1CqRaA")
        }
        if changesName, doc.setArtwork(modelName.trimmingCharacters(in: .whitespacesAndNewlines), for: "ArtworkDeviceProductDescription") {
            doc.set(modelName.trimmingCharacters(in: .whitespacesAndNewlines), for: "Z/dqyWS6OZTRy10UcmUAhw")
            doc.set(modelName.trimmingCharacters(in: .whitespacesAndNewlines), for: "bbtR9jQx50Fv5Af/affNtA")
        }
        doc.applyRegion(salesRegion: RegionPreset.all.first { $0.id == regionID },
                        regionCode: RegionPreset.all.first { $0.id == regionCodeID },
                        skipCreatingRegionInfoOnModernOS: chinaUnlockRegionMode == .fullUS)
        doc.applyModel(ModelPreset.all.first { $0.id == modelID })
        return doc
    }

    private func log(_ text: String) {
        let time = Date.now.formatted(date: .omitted, time: .standard)
        logs.append("[\(time)] \(text)")
        if logs.count > 1000 { logs.removeFirst(logs.count - 1000) }
    }
    /// Records one structured operation event. Observation only:
    /// the recorder never changes the operation, and recording is
    /// fire-and-forget — a slow record cannot affect the manager.
    /// Callers invoke this only after an operation's outcome is
    /// known, and never from inside the write path (`apply()` /
    /// `stage*` / `restore*` / `DevicePlistWriter`).
    private func recordOperationEvent(_ kind: OperationEventKind, detail: String) {
        let event = OperationEvent(kind: kind, detail: detail)
        Task { await operationEvents.record(event) }
    }
    private func failed(_ error: Error) { message = error.localizedDescription; log(error.localizedDescription) }
    private func accept(_ loaded: DocumentSnapshot) {
        snapshot = loaded; working = loaded.document
        choices = [:]; regionID = "keep"; regionCodeID = "keep"; modelID = "keep"; changesName = false; subtype = 0
        userConfirmedUnverifiedAICombination = false
        cacheOptionChoice = .keep
        wapiChoice = .keep
        modelName = loaded.document.artwork["ArtworkDeviceProductDescription"] as? String ?? ""
    }
    func clearStaged() {
        if let snapshot { accept(snapshot) }
    }

    /// Test-only entry point: loads a fixture snapshot so staging and
    /// preview logic can be verified without a device or signing.
    /// Production code never calls this; it only resets staged state
    /// through the same `accept` path as a real read.
    func loadSnapshotForTests(_ snapshot: DocumentSnapshot) { accept(snapshot) }

    // MARK: - China Unlock

    /// True when the loaded document belongs to hardware that
    /// natively supports Apple Intelligence (exact-match product-type
    /// list in `DeviceAIEligibility`). The document's product type is
    /// the source here — it is the device the file belongs to — and
    /// on a live read it agrees with the profiler's live product
    /// type. Unknown or absent product type reads as non-native, so
    /// the full 10-item proposal is built (2 eSIM + region code + 7 AI).
    /// This is a deliberate availability default, not a fail-closed
    /// gate: unlisted hardware (including future models not yet in the
    /// list) stays unlockable — see the #178 decision (2026-11-15).
    /// The fail-closed gate for model-dependent writes is
    /// `deviceModelDecision`, which already refuses SiriMode on
    /// unknown models.
    var isNativeAppleIntelligence: Bool {
        guard let productType = (working ?? snapshot?.document)?.extra[GestaltKeys.productType] as? String else {
            return false
        }
        return DeviceAIEligibility.isNativeAppleIntelligence(productType: productType)
    }

    /// The fail-closed model decision for this document (see
    /// `DeviceModelSupport`): known only with a verified mapping
    /// entry — an exact product-type entry, or a recorded original
    /// regulatory model that is itself a verified entry. Unknown
    /// product type or regulatory model reads as unknown with a
    /// reason; there is no family or prefix inference.
    private var deviceModelDecision: DeviceModelDecision {
        guard let document = working ?? snapshot?.document else {
            return .unknown(reason: L("No US regulatory model known for this device — region code only."))
        }
        let productType = document.extra[GestaltKeys.productType] as? String ?? ""
        let originalRegModel = snapshot?.originalValue(for: GestaltKeys.modelNumber) as? String
            ?? document.extra[GestaltKeys.modelNumber] as? String
        return DeviceModelSupport.decision(for: productType, originalRegModel: originalRegModel)
    }

    /// True while the full China Unlock is staged (not yet applied):
    /// eSIM flags enabled, region code US and all seven AI presets
    /// enabled — or, on hardware that natively supports Apple
    /// Intelligence, eSIM and region only, with the seven AI presets
    /// skipped by nativeness instead of staged (see
    /// `stageChinaUnlock`).
    var isChinaUnlockStaged: Bool {
        guard hasDocument else { return false }
        return cacheOptionChoice == .enable
            && regionCodeID == ChinaUnlock.regionCodeID
            && (isNativeAppleIntelligence
                || ChinaUnlock.aiCapabilityIDs.allSatisfy { (choices[$0] ?? .keep) == .enable })
    }

    /// Region code shown by the staged preview (`LL` once unlocked).
    var previewRegionCode: String? { preview?.extra[GestaltKeys.regionCode] as? String }

    var previewESIMFlags: CachedOptionFlags? {
        guard let preview else { return nil }
        return try? DeviceCacheOptions.flags(in: preview)
    }

    var isESIMUnlockedInPreview: Bool { previewESIMFlags == .enabled }

    var chinaUnlockEnabledAICapabilityIDs: Set<String> {
        guard let fields = preview?.extra else { return [] }
        // An AI capability reads as enabled when every one of its keys
        // holds the capability's own staged value — boolean true for
        // most, but SiriMode=2 for siriAIMode. Comparing against a
        // hardcoded 1 would never count siriAIMode as enabled.
        return Set(ChinaUnlock.aiCapabilities.filter { capability in
            capability.keys.allSatisfy { key in
                guard let field = fields[key] else { return false }
                return GestaltDocument.valuesEqual(field, capability.values[key] ?? capability.enabled)
            }
        }.map(\.id))
    }

    var chinaUnlockAIEnabledCount: Int { chinaUnlockEnabledAICapabilityIDs.count }

    /// True when the preview already shows the full unlock, whether it was
    /// just staged or applied in an earlier session: eSIM enabled, region
    /// code LL and all seven AI presets enabled — or, on hardware that
    /// natively supports Apple Intelligence, eSIM enabled and region
    /// code LL with the seven AI presets skipped by nativeness. The
    /// sales-region suffix and the regulatory model number are never
    /// part of the unlock, so they are not required here.
    var isChinaUnlockedInPreview: Bool {
        isESIMUnlockedInPreview && previewRegionCode == "LL"
            && (isNativeAppleIntelligence
                || chinaUnlockAIEnabledCount == ChinaUnlock.aiCapabilityIDs.count)
    }

    /// True while the AI-only preset is staged: all seven AI presets
    /// enabled. This is the AI part of the one-tap unlock, staged on its
    /// own; eSIM and region are untouched. It is not blocked by the eSIM
    /// cache layout, because the seven AI keys are CacheExtra values and do
    /// not need the layout to resolve.
    var isChinaAIOnlyStaged: Bool {
        guard hasDocument else { return false }
        return ChinaUnlock.aiCapabilityIDs.allSatisfy { (choices[$0] ?? .keep) == .enable }
    }

    /// True when the preview already shows all seven AI presets enabled,
    /// whether staged now or applied in an earlier session.
    var isChinaAIOnlyApplied: Bool {
        chinaUnlockAIEnabledCount == ChinaUnlock.aiCapabilityIDs.count
    }

    /// True while the standalone Siri AI Mode preset is staged:
    /// only the SiriMode key. Unlike the AI-only preset this one is
    /// allowed on native hardware (an explicit single-item opt-in),
    /// so nativeness never clears it; the unknown-model refusal
    /// lives in `stageChinaSiriAIMode`, not here.
    var isChinaSiriAIModeStaged: Bool {
        guard hasDocument else { return false }
        return (choices[ChinaUnlock.siriAIModeID] ?? .keep) == .enable
    }

    /// True when the preview already shows SiriMode set to 2,
    /// whether staged now or applied in an earlier session. This
    /// checks the SiriMode key directly for the value 2: the shared
    /// AI-enabled count only recognizes a value of 1, so it can
    /// never report SiriMode as enabled.
    var isChinaSiriAIModeApplied: Bool {
        guard let fields = preview?.extra else { return false }
        return (fields[GestaltKeys.siriMode] as? NSNumber)?.intValue == 2
    }

    /// True while the eSIM+region preset is staged: eSIM flags enabled
    /// and region code US. This is the eSIM+region part of the one-tap
    /// unlock, staged on its own; the seven AI presets are untouched.
    var isChinaESIMRegionStaged: Bool {
        guard hasDocument else { return false }
        return cacheOptionChoice == .enable && regionCodeID == ChinaUnlock.regionCodeID
    }

    /// True when the preview already shows eSIM enabled and region code
    /// LL, whether staged now or applied in an earlier session.
    var isChinaESIMRegionApplied: Bool {
        isESIMUnlockedInPreview && previewRegionCode == "LL"
    }

    /// Read-only "Modified Values" report: fields in the live-read
    /// document whose current value differs from the recorded original.
    /// Computed on demand from the snapshot; never stages or writes
    /// anything.
    var modifiedValuesReport: ModifiedValuesReport {
        ModifiedValues.report(for: snapshot)
    }

    // MARK: - AI readiness checkup (item 4)

    /// Live on-device probe answers (MGCopyAnswer). `nil` means the probe
    /// could not answer (simulator, or the key is unreadable) — the
    /// checkup renders "live: unknown", never a faked value.
    @Published var liveRegionCode: String?
    @Published var liveRegModel: String?
    @Published var liveAIEnabled: Bool?

    /// Refreshes the live probe answers. Read-only; safe to call from the
    /// checkup card's `onAppear`. The three MGCopyAnswer queries run off
    /// the main thread (the live query can be slow) and the results are
    /// published back on the main actor.
    func refreshLiveProbe() async {
        let (region, regModel, aiEnabled) = await Task.detached(priority: .userInitiated) {
            let region = LiveGestaltProbe.queryString(GestaltKeys.regionCode)
            let regModel = LiveGestaltProbe.queryString(GestaltKeys.modelNumber)
            let aiEnabled = Capability.all.first { $0.id == "ai" }.flatMap { capability in
                capability.keys.first.flatMap { LiveGestaltProbe.queryBool($0) }
            }
            return (region, regModel, aiEnabled)
        }.value
        liveRegionCode = region
        liveRegModel = regModel
        liveAIEnabled = aiEnabled
    }

    // MARK: - MG monitor (Stage 4)

    /// Monitor rows for every database key (three sources side by
    /// side), or empty before the first refresh. The monitor never
    /// shows an empty list as a result: on a sentinel-blocked build
    /// the rows carry `.readFailed` and the view shows the banner.
    @Published private(set) var monitorRows: [MGMonitorRow] = []
    /// When the live values in `monitorRows` were read.
    @Published private(set) var monitorReadAt: Date?
    /// The version sentinel for the current iOS build. Unknown until
    /// the first refresh classifies the build — never assumed
    /// supported before classification.
    @Published private(set) var monitorSentinel: VersionSentinelState = .unknownBuild(build: "")

    /// Refreshes the monitor rows. Read-only; safe to call from the
    /// monitor view's `onAppear` or its refresh button. The 77 live
    /// MGCopyAnswer queries run off the main thread and the rows are
    /// published back on the main actor. The monitor refreshes on
    /// demand only — no timer polls the device.
    ///
    /// Sources: original values come from the first-read snapshot,
    /// staged values from the working document (or the snapshot when
    /// there is no working document — no staged changes exist then),
    /// live values from MGCopyAnswer. The slot probe resolves the
    /// layout from the snapshot document and reads the slot byte from
    /// the snapshot and the working document; the live column for a
    /// slot key is the MGCopyAnswer answer. A plaintext key (the
    /// parallax key) answers under its readable name, so the live
    /// query retries with it when the obfuscated key returns nothing.
    func refreshMonitor() async {
        let identity = SystemDeviceIdentitySource()
        let productType = preview?.extra[GestaltKeys.productType] as? String ?? identity.productType
        let iosVersion = identity.osVersion ?? ""
        let sentinel = VersionSentinel.state(forBuild: identity.osBuild)
        let livePairs = await Task.detached(priority: .userInitiated) {
            MGDatabase.all.map { record -> (String, MGValue?) in
                let value = LiveGestaltProbe.query(record.obfuscatedName)
                    ?? (record.readableName != record.obfuscatedName
                        ? LiveGestaltProbe.query(record.readableName) : nil)
                return (record.obfuscatedName, value.flatMap(MGValue.fromPlistValue))
            }
        }.value
        let liveByKey = Dictionary(
            livePairs.compactMap { pair in pair.1.map { (pair.0, $0) } },
            uniquingKeysWith: { first, _ in first })
        let liveAt = Date()
        let snapshotDoc = snapshot?.document
        let stagedDoc = working ?? snapshotDoc
        let layout = snapshotDoc.flatMap {
            try? LayoutResolver.resolve(cacheUUID: $0.cacheUUID, cacheData: $0.cacheData)
        }
        monitorSentinel = sentinel
        monitorReadAt = liveAt
        monitorRows = MGMonitor.rows(for: MGDatabase.all.map { record in
            MGMonitorInput(
                record: record,
                original: value(of: record, in: snapshotDoc),
                staged: value(of: record, in: stagedDoc),
                live: liveByKey[record.obfuscatedName],
                liveReadAt: liveAt,
                slot: slotProbe(for: record, snapshotDoc: snapshotDoc, stagedDoc: stagedDoc,
                                layout: layout, liveByKey: liveByKey),
                productType: productType,
                iosVersion: iosVersion,
                sentinel: sentinel)
        }, now: liveAt)
    }

    /// The value of a record in a document. A plaintext key is
    /// staged under its readable name, so the lookup retries with it
    /// when the obfuscated key is absent.
    private func value(of record: MGKeyRecord, in document: GestaltDocument?) -> MGValue? {
        guard let document else { return nil }
        let raw = document.extra[record.obfuscatedName]
            ?? (record.readableName != record.obfuscatedName
                ? document.extra[record.readableName] : nil)
        return raw.flatMap(MGValue.fromPlistValue)
    }

    /// The slot probe for a record: the layout-resolved slot number
    /// and the slot byte at each source. `nil` when the layout did
    /// not resolve, or the key has no slot on this layout — unknown,
    /// never a guessed slot.
    private func slotProbe(for record: MGKeyRecord, snapshotDoc: GestaltDocument?,
                           stagedDoc: GestaltDocument?, layout: MobileGestaltCacheLayout?,
                           liveByKey: [String: MGValue]) -> MGSlotProbe? {
        guard let layout, let slotNumber = layout.slotIndex(forKey: record.obfuscatedName) else { return nil }
        let liveAnswer: Bool? = {
            guard case .bool(let value) = liveByKey[record.obfuscatedName] else { return nil }
            return value
        }()
        func slotByte(in document: GestaltDocument?) -> Bool? {
            guard let document else { return nil }
            switch record.obfuscatedName {
            case DeviceCacheOptions.audioIntelligenceKey, DeviceCacheOptions.personalTranslatorKey:
                return DeviceCacheOptions.advAISlotValue(record.obfuscatedName, in: document, using: layout)
            case DeviceCacheOptions.greenTeaKey:
                return (try? DeviceCacheOptions.flags(in: document, using: layout))?.greenTea
            case DeviceCacheOptions.notGreenTeaKey:
                return (try? DeviceCacheOptions.flags(in: document, using: layout))?.notGreenTea
            case DeviceCacheOptions.wapiKey:
                return try? DeviceCacheOptions.wapi(in: document, using: layout)
            default:
                return nil
            }
        }
        return MGSlotProbe(slotNumber: slotNumber,
                           originalByte: slotByte(in: snapshotDoc),
                           stagedByte: slotByte(in: stagedDoc),
                           liveAnswer: liveAnswer,
                           nativeBaseline: record.slot?.nativeBaseline)
    }

    /// Slot and key conflicts on native-AI hardware, computed from the staged
    /// preview. The Personal Translator case is split per layer: a CacheData
    /// slot reading 0 against its native baseline of 1, and a CacheExtra key
    /// explicitly 0, are separate conflicts. The Audio Intelligence case
    /// stays slot-only (see the #178 note in AIReadinessCheckup.swift): the
    /// unlock sets CacheExtra `audioIntelligence` = 1 by definition, and
    /// whether that key alone harms native-AI iPhones is unverified. An
    /// unresolvable slot means "unknown", never a conflict.
    var aiConflicts: [AIConflict] {
        guard let preview,
              let productType = preview.extra[GestaltKeys.productType] as? String,
              DeviceAIEligibility.isNativeAppleIntelligence(productType: productType),
              let layout = try? LayoutResolver.resolve(cacheUUID: preview.cacheUUID, cacheData: preview.cacheData) else { return [] }
        var conflicts: [AIConflict] = []
        let ptBaseline = DeviceAIEligibility.nativeAdvAISlotValue(
            key: DeviceCacheOptions.personalTranslatorKey, productType: productType)
        if ptBaseline == true {
            let slotValue = DeviceCacheOptions.advAISlotValue(
                DeviceCacheOptions.personalTranslatorKey, in: preview, using: layout)
            if slotValue == false {
                conflicts.append(.personalTranslatorSlotDisabled(
                    slot: layout.slotIndex(forKey: DeviceCacheOptions.personalTranslatorKey)))
            }
            if (preview.extra[DeviceCacheOptions.personalTranslatorKey] as? NSNumber)?.intValue == 0 {
                conflicts.append(.personalTranslatorKeyDisabled)
            }
        }
        let audioBaseline = DeviceAIEligibility.nativeAdvAISlotValue(
            key: DeviceCacheOptions.audioIntelligenceKey, productType: productType)
        if audioBaseline == false,
           DeviceCacheOptions.advAISlotValue(
               DeviceCacheOptions.audioIntelligenceKey, in: preview, using: layout) == true {
            conflicts.append(.audioIntelligenceEnabled(
                slot: layout.slotIndex(forKey: DeviceCacheOptions.audioIntelligenceKey)))
        }
        return conflicts
    }

    /// The staging-guard decision for a document, or `nil` when the guard
    /// has no input. `nil` has two distinct causes, and callers must not
    /// treat them as a block: the layout did not resolve at all (the
    /// eSIM layout gate is the fail-closed enforcement for that case), or
    /// the layout carries no resolved AdvAI slot index at all — the
    /// offline profile and the simulator, where the slots are
    /// unobservable rather than conflicting. The pure guard
    /// (`AIStagingGuard.decide`) still fails closed on an unresolvable
    /// slot when a caller can establish the slot should have resolved;
    /// the manager cannot establish that (a real device scan can
    /// legitimately find no AdvAI descriptors), so it reports no decision
    /// instead of blocking the unlock on unobservable slots. `nil` is
    /// therefore "no guard input", never "safe" and never "blocked".
    /// `proposedUnlock` evaluates the China Unlock proposal (both guarded
    /// CacheExtra keys staged as 1) instead of the document's current
    /// staged values — what Fix is about to stage, rather than what is
    /// already staged.
    static func stagingDecision(for document: GestaltDocument,
                                layout: MobileGestaltCacheLayout,
                                liveAIEnabled: Bool?,
                                userConfirmedUnverifiedCombination: Bool,
                                proposedUnlock: Bool) -> AIStagingDecision? {
        let audioIndex = layout.slotIndex(forKey: DeviceCacheOptions.audioIntelligenceKey)
        let translatorIndex = layout.slotIndex(forKey: DeviceCacheOptions.personalTranslatorKey)
        guard audioIndex != nil || translatorIndex != nil else { return nil }
        let productType = document.extra[GestaltKeys.productType] as? String ?? ""
        var request = AIStagingRequest(productType: productType)
        if proposedUnlock {
            request.audioIntelligenceExtra = true
            request.personalTranslatorExtra = true
        } else {
            request.audioIntelligenceExtra = (document.extra[DeviceCacheOptions.audioIntelligenceKey] as? NSNumber)?.boolValue
            request.personalTranslatorExtra = (document.extra[DeviceCacheOptions.personalTranslatorKey] as? NSNumber)?.boolValue
        }
        request.audioIntelligenceSlot = DeviceCacheOptions.advAISlotValue(
            DeviceCacheOptions.audioIntelligenceKey, in: document, using: layout)
        request.personalTranslatorSlot = DeviceCacheOptions.advAISlotValue(
            DeviceCacheOptions.personalTranslatorKey, in: document, using: layout)
        request.audioIntelligenceSlotIndex = audioIndex
        request.personalTranslatorSlotIndex = translatorIndex
        request.liveAIEnabled = liveAIEnabled
        request.siriHubLive = LiveGestaltProbe.queryBool(SiriHubGuard.siriHubKey)
        request.userConfirmedUnverifiedCombination = userConfirmedUnverifiedCombination
        return AIStagingGuard.decide(request)
    }

    /// The guard decision for the combination currently staged in the
    /// preview, or `nil` when the slots are unobservable (see
    /// `stagingDecision(for:layout:...)`). The checkup surfaces a
    /// `.block`/`.warn` decision in its eSIM/conflict factor with the
    /// decision's specific reason.
    var aiStagingDecision: AIStagingDecision? {
        guard let preview,
              let layout = try? LayoutResolver.resolve(cacheUUID: preview.cacheUUID, cacheData: preview.cacheData) else { return nil }
        return Self.stagingDecision(for: preview, layout: layout, liveAIEnabled: liveAIEnabled,
                                    userConfirmedUnverifiedCombination: userConfirmedUnverifiedAICombination,
                                    proposedUnlock: false)
    }

    /// The guard decision for the China Unlock proposal (all seven AI keys
    /// staged as 1), evaluated on the current preview, or `nil` when the
    /// slots are unobservable. Fix evaluates this before staging: it
    /// answers whether the combination Fix is about to stage is blocked,
    /// warned, or allowed.
    var proposedUnlockStagingDecision: AIStagingDecision? {
        guard let preview,
              let layout = try? LayoutResolver.resolve(cacheUUID: preview.cacheUUID, cacheData: preview.cacheData) else { return nil }
        return Self.stagingDecision(for: preview, layout: layout, liveAIEnabled: liveAIEnabled,
                                    userConfirmedUnverifiedCombination: userConfirmedUnverifiedAICombination,
                                    proposedUnlock: true)
    }

    /// The 4-factor readiness checkup for the staged preview, or `nil`
    /// when no document is loaded.
    var aiReadinessCheckup: AIReadinessCheckup? {
        guard let preview, let snapshot else { return nil }
        let productType = preview.extra[GestaltKeys.productType] as? String
            ?? snapshot.document.extra[GestaltKeys.productType] as? String ?? ""
        return AIReadinessCheckup.evaluate(
            regionCode: preview.extra[GestaltKeys.regionCode] as? String,
            regModel: preview.extra[GestaltKeys.modelNumber] as? String,
            esimEnabled: isESIMUnlockedInPreview,
            conflicts: aiConflicts,
            aiEnabledCount: chinaUnlockAIEnabledCount,
            aiTotal: ChinaUnlock.aiCapabilities.count,
            productType: productType,
            liveRegionCode: liveRegionCode,
            liveRegModel: liveRegModel,
            liveAIEnabled: liveAIEnabled,
            stagingDecision: aiStagingDecision)
    }

    /// Stages slot-only repairs for the detected AI conflicts: each slot
    /// is set to its native baseline through the normal staging path, so
    /// the repair still goes through review + backup + readback. A
    /// CacheExtra key that was explicitly disabled is restored to its
    /// recorded original. Returns true when anything was staged.
    @discardableResult
    func repairAIConflicts() -> Bool {
        guard !isBusy, var document = working, let snapshot,
              let productType = document.extra[GestaltKeys.productType] as? String else { return false }
        var staged = false
        for conflict in aiConflicts {
            switch conflict {
            case .personalTranslatorSlotDisabled:
                if let baseline = DeviceAIEligibility.nativeAdvAISlotValue(
                       key: DeviceCacheOptions.personalTranslatorKey, productType: productType),
                   let current = DeviceCacheOptions.advAISlotValue(
                       DeviceCacheOptions.personalTranslatorKey, in: document),
                   current != baseline {
                    do {
                        try document.setAdvAISlot(DeviceCacheOptions.personalTranslatorKey, value: baseline)
                        staged = true
                    } catch { /* Layout changed under us; leave it unstaged. */ }
                }
            case .personalTranslatorKeyDisabled:
                if (document.extra[DeviceCacheOptions.personalTranslatorKey] as? NSNumber)?.intValue == 0 {
                    document.set(snapshot.originalValue(for: DeviceCacheOptions.personalTranslatorKey),
                                 for: DeviceCacheOptions.personalTranslatorKey)
                    staged = true
                }
            case .audioIntelligenceEnabled:
                if let baseline = DeviceAIEligibility.nativeAdvAISlotValue(
                       key: DeviceCacheOptions.audioIntelligenceKey, productType: productType),
                   let current = DeviceCacheOptions.advAISlotValue(
                       DeviceCacheOptions.audioIntelligenceKey, in: document),
                   current != baseline {
                    do {
                        try document.setAdvAISlot(DeviceCacheOptions.audioIntelligenceKey, value: baseline)
                        staged = true
                    } catch { /* Layout changed under us; leave it unstaged. */ }
                }
            }
        }
        if staged { working = document }
        return staged
    }

    /// Repairs the AI baseline in the staged working document, so a
    /// one-tap unlock (or AI-only staging) leaves a complete and
    /// consistent AI baseline instead of a partial one. Called at the
    /// end of `stageChinaUnlock` and `stageChinaAIOnly` (staging only
    /// — the repair still goes through review + backup + readback
    /// like every other change).
    ///
    /// - CacheData slots: each AdvAI slot is set to its native
    ///   baseline (Personal Translator #266 = 1, Audio Intelligence
    ///   #178 = 0) when a baseline is known for this hardware
    ///   (`DeviceAIEligibility.nativeAdvAISlotValue`, native hardware
    ///   only) and the slot resolves and disagrees. Correct values are
    ///   left untouched; unresolvable slots are left alone (unknown,
    ///   never guessed). This matches Erosion-CN's one-click fix as of
    ///   main `1d5608dd` (v1.0.3, `applyAppleIntelligenceOneClickFix`,
    ///   `GestaltStore.swift:903`): it repairs #178/#266 back to their
    ///   native values and only forces the 3 main AI keys
    ///   (`appIntellAllKeys`) to 1 on non-native hardware — the two
    ///   slots are not in that step's key list. (Whether an older
    ///   Erosion-CN version forced all AI slots to 1 was not verified;
    ///   see Stage 1 U4.)
    /// - CacheExtra keys: when AI staging is active (the seven AI
    ///   choices are staged `.enable`), any AI key absent from the
    ///   working document is filled with its staged value. Present
    ///   values are left untouched. On native hardware the AI keys are
    ///   deliberately NOT filled: the #178 decision skips them there,
    ///   and the slots above are the only baseline repair that applies.
    /// Returns true when anything was staged.
    @discardableResult
    func fixAIBaseline() -> Bool {
        guard !isBusy, var document = working,
              let productType = document.extra[GestaltKeys.productType] as? String else { return false }
        var staged = false
        // CacheData slots to their native baselines (native only:
        // `nativeAdvAISlotValue` returns nil where no baseline is
        // known, so non-native hardware is left alone).
        for key in [DeviceCacheOptions.personalTranslatorKey, DeviceCacheOptions.audioIntelligenceKey] {
            guard let baseline = DeviceAIEligibility.nativeAdvAISlotValue(key: key, productType: productType),
                  let current = DeviceCacheOptions.advAISlotValue(key, in: document),
                  current != baseline else { continue }
            do {
                try document.setAdvAISlot(key, value: baseline)
                staged = true
            } catch {
                // Layout changed under us; leave it unstaged rather
                // than staging a slot we cannot verify.
            }
        }
        // CacheExtra keys: fill absent AI keys with their staged
        // values, only where AI staging is active.
        let aiStaged = ChinaUnlock.aiCapabilityIDs.allSatisfy { (choices[$0] ?? .keep) == .enable }
        if aiStaged {
            for capability in ChinaUnlock.aiCapabilities {
                for key in capability.keys where document.extra[key] == nil {
                    document.set(capability.values[key] ?? capability.enabled, for: key)
                    staged = true
                }
            }
        }
        if staged { working = document }
        return staged
    }

    /// One-tap fix for the AI readiness checkup: repairs any slot
    /// conflicts first, then evaluates the staging guard on the China
    /// Unlock proposal before staging it. A `.block` decision holds the
    /// staging — the reason is shown, while a repair staged above stays
    /// staged for review. A `.warn` decision proceeds: tapping Fix on
    /// the checkup card, after the reason was shown there, is the
    /// explicit confirmation, and it is recorded so the checkup stops
    /// reporting the warned combination as not ready. Never writes
    /// directly; the caller opens the existing review sheet (same as the
    /// unlock card's path).
    @discardableResult
    func fixAIReadiness() -> Bool {
        var didSomething = false
        if repairAIConflicts() { didSomething = true }
        // Re-evaluate on the (possibly repaired) preview: a slot repaired
        // to its native baseline no longer blocks staging.
        if let decision = proposedUnlockStagingDecision {
            if decision.requiresSlotRepair {
                message = decision.reason
                log(decision.reason)
                return didSomething
            }
            if decision.requiresExplicitConfirmation {
                userConfirmedUnverifiedAICombination = true
                didSomething = true
            }
        }
        if !isChinaUnlockedInPreview, stageChinaUnlock() { didSomething = true }
        return didSomething
    }

    /// The reason the cache layout cannot be resolved on this device, if
    /// any. `nil` means the runtime scan matched this document. This is
    /// the UI lock state for the eSIM/WAPI switches: when it is non-nil
    /// the switches stay locked and the reason is shown. Presentation
    /// only; the stage-time throw remains the enforcement point.
    var cacheLayoutError: String? {
        guard let working else { return L("Read MobileGestalt first.") }
        do {
            _ = try LayoutResolver.resolve(cacheUUID: working.cacheUUID, cacheData: working.cacheData)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// The reason the eSIM cache layout cannot be verified, if any.
    /// `nil` means the layout resolves and the eSIM flags can be read,
    /// so the full group may be staged. Read-only: it never writes.
    var chinaUnlockESIMLayoutError: String? {
        guard let working else { return L("Read MobileGestalt first.") }
        do {
            _ = try DeviceCacheOptions.flags(in: working)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Stages the full China Unlock: eSIM cache flags, region code US and
    /// the seven Apple Intelligence presets — exactly the 10 items, in either
    /// region mode. On hardware that natively supports Apple Intelligence
    /// only the 3 non-AI items are staged (eSIM + region code) and the
    /// seven AI presets are skipped, never staged — staging them would
    /// only record type-change diffs (1 → true) for values that are
    /// already on. Nothing is written here; the user still reviews the
    /// changes and applies them, and a restart is required before they
    /// take effect. The sales-region suffix, the regulatory model number,
    /// `siriOnDevice` and WAPI are never staged: a regulatory model that
    /// does not match the hardware makes the system discard the whole
    /// MobileGestalt cache at boot and rebuild it from factory data, so
    /// the region change does not stick.
    ///
    /// This is an explicit user action, so it is deliberately not gated
    /// by the AI staging guard (see `AIStagingGuard`): it stages
    /// CacheExtra keys only and never writes a CacheData slot, so a
    /// pre-existing slot conflict is surfaced by the checkup with a
    /// repair path instead of disabling the unlock. The guard is enforced
    /// on the checkup card's Fix path (`fixAIReadiness`).
    ///
    /// If the eSIM cache layout cannot be verified, the whole group is
    /// stopped and the reason is shown (`message`); region code and AI
    /// are NOT staged as a fallback. They remain settable through their
    /// individual preset entries.
    @discardableResult
    func stageChinaUnlock() -> Bool {
        guard !isBusy else { return false }
        if let reason = chinaUnlockESIMLayoutError {
            message = reason
            log(reason)
            return false
        }
        guard stageCacheOption(.enable) else { return false }
        regionCodeID = ChinaUnlock.regionCodeID
        regionID = "keep"
        // Native Apple Intelligence hardware already supports the seven
        // AI presets: staging them would claim a change that is not
        // one. Skip them; the staged flag reads the skip as satisfied
        // (see `isChinaUnlockStaged`).
        if !isNativeAppleIntelligence {
            for id in ChinaUnlock.aiCapabilityIDs { choices[id] = .enable }
        }
        // Complete the AI baseline: repair the two AdvAI CacheData
        // slots to their native values and fill any absent AI keys
        // (native hardware: slots only, keys stay skipped).
        _ = fixAIBaseline()
        return true
    }

    /// Stages a restore of the full China Unlock: eSIM flags back to the
    /// recorded originals, region code back to its recorded original and
    /// the seven AI presets back to their recorded originals (`.disable`
    /// removes keys that were originally absent). `siriOnDevice` and WAPI
    /// are left untouched. The sales-region suffixes and the model number
    /// are also restored when the stored mode is Full US, so an unlock
    /// applied by an older build can still be reverted.
    @discardableResult
    func restoreChinaUnlock() -> Bool {
        guard stageCacheOption(.restoreOriginal) else { return false }
        regionCodeID = "keep"
        regionID = "keep"
        if let snapshot, var document = working {
            // The region overlay is preview-only, so stopping the overlay
            // alone would leave a previously applied `LL` in `working`.
            // Reset the working document itself to the recorded original.
            document.set(snapshot.originalValue(for: GestaltKeys.regionCode), for: GestaltKeys.regionCode)
            if chinaUnlockRegionMode == .fullUS {
                // Full-US staging also writes the sales-region suffixes
                // and the regulatory model number; restore those too.
                document.set(snapshot.originalValue(for: GestaltKeys.regionInfo), for: GestaltKeys.regionInfo)
                document.set(snapshot.originalValue(for: GestaltKeys.legacyRegionInfo), for: GestaltKeys.legacyRegionInfo)
                document.set(snapshot.originalValue(for: GestaltKeys.modelNumber), for: GestaltKeys.modelNumber)
            }
            // ADR-2-02: restore the two AdvAI CacheData slots to their
            // snapshot originals. A failed slot is logged and does not
            // stop the rest of the restore.
            for outcome in AdvAISlotRestore.restore(in: &document, from: snapshot.document) {
                if case .failed(let key, let reason) = outcome {
                    log("[restore] slot \(key) could not be restored: \(reason)")
                }
            }
            working = document
        }
        for id in ChinaUnlock.aiCapabilityIDs { choices[id] = .disable }
        return true
    }

    /// Stages only the seven Apple Intelligence presets — the AI part of the
    /// one-tap unlock, without eSIM or region. Deliberately not gated by
    /// the eSIM cache layout (see `chinaUnlockESIMLayoutError`): the AI
    /// keys are CacheExtra values and do not need the layout. Like the
    /// one-tap, this is an explicit user action, so it is not gated by
    /// the AI staging guard; the checkup surfaces any slot conflict with
    /// a repair path. On hardware that natively supports Apple
    /// Intelligence there is nothing to stage — the presets are already
    /// on — so staging is refused with the reason shown (`message`)
    /// instead of recording type-change diffs (1 → true).
    @discardableResult
    func stageChinaAIOnly() -> Bool {
        guard !isBusy else { return false }
        if isNativeAppleIntelligence {
            let reason = L("Apple Intelligence is already enabled natively on this device — nothing to stage.")
            message = reason
            log(reason)
            return false
        }
        for id in ChinaUnlock.aiCapabilityIDs { choices[id] = .enable }
        // Complete the AI baseline: repair the two AdvAI CacheData
        // slots to their native values and fill any absent AI keys.
        _ = fixAIBaseline()
        return true
    }

    /// Stages a restore of the AI-only preset: the seven AI presets back to
    /// their recorded originals (`.disable` removes keys that were
    /// originally absent). eSIM and region are left untouched. The two
    /// AdvAI CacheData slots are restored to their snapshot originals
    /// too (ADR-2-02): the AI-only staging path repairs them via
    /// `fixAIBaseline`, so its restore path must cover them.
    @discardableResult
    func restoreChinaAIOnly() -> Bool {
        guard !isBusy else { return false }
        if let snapshot, var document = working {
            let outcomes = AdvAISlotRestore.restore(in: &document, from: snapshot.document)
            for outcome in outcomes {
                if case .failed(let key, let reason) = outcome {
                    log("[restore] slot \(key) could not be restored: \(reason)")
                }
            }
            if outcomes.contains(where: \.isRestored) { working = document }
        }
        for id in ChinaUnlock.aiCapabilityIDs { choices[id] = .disable }
        return true
    }

    /// Stages only Siri AI Mode (SiriMode=2) — the standalone
    /// single-item preset, without eSIM, region, or the other AI
    /// keys. Deliberately not gated by the eSIM cache layout: the
    /// SiriMode key is a CacheExtra value and does not need the
    /// layout. Unlike the AI-only preset this one is ALLOWED on
    /// hardware that natively supports Apple Intelligence — that is
    /// the point: an explicit single-item opt-in on a device whose
    /// Siri AI already works, with the experimental warning shown
    /// by the card. It IS gated by the fail-closed model decision
    /// (`deviceModelDecision`): an unknown model refuses with the
    /// reason shown (`message`), so a guessed device never gets a
    /// staged SiriMode value.
    @discardableResult
    func stageChinaSiriAIMode() -> Bool {
        guard !isBusy else { return false }
        if case .unknown(let reason) = deviceModelDecision {
            message = reason
            log(reason)
            return false
        }
        choices[ChinaUnlock.siriAIModeID] = .enable
        return true
    }

    /// Stages a restore of the Siri AI Mode preset: SiriMode back to
    /// its recorded original (`.disable` removes the key when it was
    /// originally absent). eSIM, region, and the other AI presets
    /// are left untouched. Restoring is never gated by the model
    /// decision — returning to the original is always safe.
    @discardableResult
    func restoreChinaSiriAIMode() -> Bool {
        guard !isBusy else { return false }
        choices[ChinaUnlock.siriAIModeID] = .disable
        return true
    }

    /// Stages only the eSIM cache flags and the region code US (LL) — the
    /// eSIM+region part of the one-tap unlock, without the seven AI presets.
    /// Guarded by the eSIM cache layout exactly like `stageChinaUnlock`:
    /// if the layout cannot be verified, the preset is stopped and the
    /// reason is shown (`message`).
    @discardableResult
    func stageChinaESIMRegion() -> Bool {
        guard !isBusy else { return false }
        if let reason = chinaUnlockESIMLayoutError {
            message = reason
            log(reason)
            return false
        }
        guard stageCacheOption(.enable) else { return false }
        regionCodeID = ChinaUnlock.regionCodeID
        regionID = "keep"
        return true
    }

    /// Stages a restore of the eSIM+region preset: eSIM flags back to the
    /// recorded originals and region code back to its recorded original.
    /// The seven AI presets are left untouched.
    @discardableResult
    func restoreChinaESIMRegion() -> Bool {
        guard stageCacheOption(.restoreOriginal) else { return false }
        regionCodeID = "keep"
        regionID = "keep"
        if let snapshot, var document = working {
            // The region overlay is preview-only, so stopping the overlay
            // alone would leave a previously applied `LL` in `working`.
            // Reset the working document itself to the recorded original.
            document.set(snapshot.originalValue(for: GestaltKeys.regionCode), for: GestaltKeys.regionCode)
            working = document
        }
        return true
    }

    @discardableResult
    func stageCacheOption(_ choice: CacheOptionChoice) -> Bool {
        guard !isBusy, var document = working, let snapshot else { return false }
        do {
            let flags: CachedOptionFlags
            switch choice {
            case .keep: flags = try DeviceCacheOptions.flags(in: snapshot.document)
            case .enable: flags = .enabled
            case .restoreOriginal: flags = try snapshot.originalCachedOptionFlags()
            }
            try document.setCacheOptions(flags)
            working = document
            cacheOptionChoice = choice
            return true
        } catch {
            failed(error)
            return false
        }
    }

    func stageWAPI(_ choice: WAPIChoice) {
        guard !isBusy, var document = working, let snapshot else { return }
        do {
            let value: Bool
            switch choice {
            case .keep: value = try DeviceCacheOptions.wapi(in: snapshot.document)
            case .disable: value = false
            case .restoreOriginal: value = try snapshot.originalWAPI()
            }
            try document.setWAPI(value)
            working = document
            wapiChoice = choice
        } catch { failed(error) }
    }

    var canRestoreCacheOption: Bool {
        guard !isBusy, let snapshot, let working,
              let original = try? snapshot.originalCachedOptionFlags(),
              let current = try? DeviceCacheOptions.flags(in: working) else { return false }
        return cacheOptionChoice != .keep || current != original
    }

    func restoreCacheOption() async {
        guard !isBusy, let before = snapshot, let pending = working else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            var restored = before.document
            try restored.setCacheOptions(before.originalCachedOptionFlags())
            let result: DocumentSnapshot
            if restored.matches(before.document) {
                result = before
            } else {
                logChanges(from: before.document, to: restored, prefix: "[restore-option] ")
                result = try await files.commit(restored, expected: before)
                needsRestart = result.source == .device
                message = L(result.source == .device
                            ? "Write verified. Some features require a device restart."
                            : "Local changes saved. Export the plist to keep a copy.")
            }
            snapshot = result
            working = before.rebasingPendingEdits(pending, onto: result.document, excluding: [], preservingCacheData: false)
            if let value = try? DeviceCacheOptions.wapi(in: pending),
               (try? DeviceCacheOptions.wapi(in: before.document)) != value { try working?.setWAPI(value) }
            cacheOptionChoice = .keep
            log("[restore-option] " + L("Original values restored."))
            await reloadBackups()
        } catch { failed(error); await reloadBackups() }
    }

    func canRestore(_ capability: Capability) -> Bool {
        guard !isBusy, let snapshot, let working else { return false }
        if (choices[capability.id] ?? .keep) != .keep { return true }
        if capability.id == "dynamicIsland" && subtype != 0 { return true }
        if capability.id == "dynamicIsland" {
            var restored = working
            capability.restoreDynamicIslandLayout(in: &restored, from: snapshot)
            if !restored.matches(working) { return true }
        }
        if capability.id == ModelPreset.restoration.id && modelID != "keep" { return true }
        return capability.keys.contains { key in
            switch (snapshot.originalValue(for: key), working.extra[key]) {
            case (nil, nil): false
            case (let a?, let b?): !GestaltDocument.valuesEqual(a, b)
            default: true
            }
        }
    }

    func restoreCapability(_ capability: Capability) async {
        guard !isBusy, let before = snapshot, let pending = working else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            var restored = before.document
            let removesAdded = choices[capability.id] == .removeAdded
            let absentKeys = removesAdded ? Set(capability.keys) : Set<String>()
            capability.apply(removesAdded ? .removeAdded : .disable, to: &restored, restoringFrom: before)
            let result: DocumentSnapshot
            if restored.matches(before.document) && absentKeys.isEmpty {
                result = before
            } else {
                for line in diffLines(before.document.extra, restored.extra) { log("[restore-field] " + line) }
                result = try await files.commit(restored, expected: before, originallyAbsentKeys: absentKeys)
                needsRestart = result.source == .device
                message = L(result.source == .device ? "Original values restored." : "Local changes saved. Export the plist to keep a copy.")
            }
            snapshot = result
            var rebased = before.rebasingPendingEdits(pending, onto: result.document, excluding: Set(capability.keys))
            capability.restoreDynamicIslandLayout(in: &rebased, from: before)
            working = rebased
            choices[capability.id] = .keep
            if capability.id == "dynamicIsland" { subtype = 0 }
            if capability.id == ModelPreset.restoration.id { modelID = "keep" }
            log("[restore-field] " + L(capability.title) + ": " + L("Original values restored."))
            await reloadBackups()
        } catch { failed(error); await reloadBackups() }
    }
    func clearLog() { logs = [] }

    // MARK: - Exploit-process logging

    private func describe(_ value: Any?) -> String {
        guard let value else { return "∅" }
        if let data = value as? Data { return "\(data.count) bytes" }
        let text = PlistValueKind.detect(value).text(for: value)
        return text.count > 80 ? String(text.prefix(80)) + "…" : text
    }

    private func diffLines(_ before: [String: Any], _ after: [String: Any], prefix: String = "") -> [String] {
        enum Difference { case line(String), nested([String]) }
        var changes: [(key: String, value: Difference)] = []
        func path(_ key: String) -> String { prefix.isEmpty ? key : prefix + "." + key }
        var matched = 0
        for (key, oldValue) in before {
            guard let newValue = after[key] else {
                changes.append((key, .line("- \(path(key))  (was \(describe(oldValue)))")))
                continue
            }
            matched += 1
            if let oldDict = oldValue as? [String: Any], let newDict = newValue as? [String: Any] {
                // Recursion identifies changed members directly; comparing
                // the whole dictionary first would traverse it again.
                let nested = diffLines(oldDict, newDict, prefix: path(key))
                if !nested.isEmpty { changes.append((key, .nested(nested))) }
            } else if !GestaltDocument.valuesEqual(oldValue, newValue) {
                changes.append((key, .line("~ \(path(key)): \(describe(oldValue)) → \(describe(newValue))")))
            }
        }
        // A second walk is needed only if some destination keys were not
        // encountered above. Ordinary value edits have no added keys.
        if matched < after.count {
            for (key, value) in after where before[key] == nil {
                changes.append((key, .line("+ \(path(key)) = \(describe(value))")))
            }
        }
        // Preserve the existing depth-first key order, sorting only branches
        // that actually produced log messages.
        changes.sort { $0.key < $1.key }
        var lines: [String] = []
        for (_, difference) in changes {
            switch difference {
            case .line(let line): lines.append(line)
            case .nested(let nested): lines.append(contentsOf: nested)
            }
        }
        return lines
    }

    private func summarize(_ document: GestaltDocument) -> [String] {
        var lines = ["CacheExtra: \(document.extra.count) keys"]
        if let cacheData = document.root["CacheData"] as? Data { lines.append("CacheData: \(cacheData.count) bytes") }
        do {
            let layout = try LayoutResolver.resolve(cacheUUID: document.cacheUUID, cacheData: document.cacheData)
            let source = LayoutResolver.runtimeLayout().map { $0 == layout } == true ? "runtime scan" : "offline profile"
            lines.append("Cache layout: \(layout.uuid), \(layout.slotCount) slots (\(source))")
            lines.append(String(format: "green-tea: index %d, offset 0x%X; not-green-tea: index %d, offset 0x%X",
                                layout.greenTeaIndex, layout.greenTeaOffset, layout.notGreenTeaIndex, layout.notGreenTeaOffset))
        } catch { lines.append("Cache offsets: " + error.localizedDescription) }
        if let model = document.artwork["ArtworkDeviceProductDescription"] as? String { lines.append("model name: \(model)") }
        if let subtype = document.artwork["ArtworkDeviceSubType"] { lines.append("subtype: \(describe(subtype))") }
        if let region = document.extra[GestaltKeys.regionCode] as? String { lines.append("region code: \(region)") }
        for key in [GestaltKeys.regionInfo, GestaltKeys.legacyRegionInfo] {
            if let info = document.extra[key] as? String { lines.append("region info: \(info)") }
        }
        if let product = document.extra[GestaltKeys.productType] as? String { lines.append("product type: \(product)") }
        return lines
    }

    private func logChanges(from original: GestaltDocument, to edited: GestaltDocument, prefix: String) {
        for line in diffLines(original.root, edited.root) { log(prefix + line) }
        for change in DeviceCacheOptions.changes(from: original, to: edited) {
            log(prefix + "CacheData.\(change.name) @\(String(format: "0x%X", change.offset)): \(change.before) → \(change.after)")
        }
    }

    func connect(showErrorAlert: Bool = true) async {
        guard !isBusy else { return }
        isBusy = true; isReading = true; status = "Checking device access…"
        log("[read] Starting MobileGestalt access")
        defer { isBusy = false; isReading = false }
        do {
            let result = try await files.loadDevice()
            accept(result); deviceAccessible = true; status = "Device connected"
            lastReadAt = Date()
            log("[read] plist: \(result.data.count) bytes")
            for line in summarize(result.document) { log("[read] " + line) }
            log(L("Device connected"))
            recordOperationEvent(.readSucceeded, detail: String(
                format: L("Read %lld bytes from the device."), result.data.count))
        } catch {
            deviceAccessible = false; status = "Device access unavailable"
            if showErrorAlert { failed(error) } else { log(error.localizedDescription) }
            recordOperationEvent(.readFailed, detail: error.localizedDescription)
        }
        await reloadBackups()
    }

    #if targetEnvironment(simulator)
    func open(_ url: URL) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard (values.fileSize ?? 0) <= 16 * 1024 * 1024 else { throw GestaltFailure("Choose a plist smaller than 16 MB.") }
            let data = try await Task.detached(priority: .userInitiated) { try Data(contentsOf: url) }.value
            let result = try await files.loadLocal(data: data, name: url.lastPathComponent)
            accept(result); status = "Local file opened"; needsRestart = false
            lastReadAt = Date()
            log("[open] \(url.lastPathComponent): \(result.data.count) bytes")
            for line in summarize(result.document) { log("[open] " + line) }
            log(L("Local file opened") + ": " + url.lastPathComponent)
            recordOperationEvent(.readSucceeded, detail: L("Local file opened") + ": " + url.lastPathComponent)
        } catch {
            failed(error)
            recordOperationEvent(.readFailed, detail: error.localizedDescription)
        }
    }

    #endif

    private func verifyImport(_ bytes: Data) async throws -> (Data, DevicePlistIdentity?) {
        if let payload = try DeviceBoundPlist.verifiedPayload(bytes) { return (payload, nil) }
        let incoming = try DevicePlistIdentity(plist: bytes)
        guard incoming.values.count >= 2 else { throw DevicePlistIdentity.incomplete }
        let empty = try DevicePlistIdentity(properties: [:])
        var trusted = (try? DevicePlistIdentity(properties: GXCopyCurrentDeviceIdentity())) ?? empty
        if trusted.values.count >= 2 {
            do { try incoming.requireMatch(with: trusted); return (bytes, trusted) }
            catch let error as SharedPlistError where error.key == DevicePlistIdentity.mismatch.key { throw error }
            catch { /* The cache may provide an additional identifier. */ }
        }
        // Only a fresh read from the actual device path is a trusted fallback.
        // Previously imported documents and user-provided backups are never used.
        do {
            let live = try await files.loadDevice()
            trusted = try trusted.mergingTrusted(DevicePlistIdentity(properties: live.document.extra))
        } catch { throw DevicePlistIdentity.unavailable }
        try incoming.requireMatch(with: trusted)
        return (bytes, trusted)
    }

    func prepareSharedPlist(_ entry: SharedPlistEntry, from inbox: SharedPlistInbox) async -> SharedImportPreparation<PlistImportOffer> {
        guard !isBusy, changeCount == 0 else { return .deferred(nil) }
        isBusy = true
        defer { isBusy = false }
        do {
            let bytes = try await inbox.readAsync(entry)
            let (payload, identity) = try await verifyImport(bytes)
            try Task.checkCancellation()
            log("[share] Device ownership verified; waiting for import confirmation")
            return .ready(PlistImportOffer(data: payload, name: entry.name, identity: identity, sharedSource: (inbox, entry)))
        } catch is CancellationError {
            return .deferred(nil)
        } catch {
            // Retry only known access/service failures, not invalid content.
            log("[share] " + error.localizedDescription)
            if !inbox.reject(entry, after: error) {
                return .deferred(error.localizedDescription)
            }
            return .rejected(error.localizedDescription)
        }
    }

    func prepareFileImport(_ url: URL) async -> PlistImportOffer? {
        guard !isBusy, changeCount == 0 else { return nil }
        isBusy = true
        defer { isBusy = false }
        do {
            let bytes = try await SharedPlistInbox.readDocumentAsync(at: url)
            let (payload, identity) = try await verifyImport(bytes)
            try Task.checkCancellation()
            return PlistImportOffer(data: payload, name: url.lastPathComponent, identity: identity, sharedSource: nil)
        } catch is CancellationError { return nil }
        catch { failed(error); return nil }
    }

    func acceptImport(_ offer: PlistImportOffer) async {
        guard !isBusy, changeCount == 0 else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            // Use the immutable bytes that were verified for this confirmation.
            if let identity = offer.identity { try DevicePlistIdentity(plist: offer.data).requireMatch(with: identity) }
            var loaded = try await files.loadLocal(data: offer.data, name: offer.name)
            loaded.ownershipVerified = true
            accept(loaded); status = "Local file opened"; needsRestart = false
            discardImport(offer)
            log("[share] Verified device plist imported: \(offer.data.count) bytes")
        } catch { failed(error) }
    }

    var canRestoreImportedPlist: Bool {
        snapshot?.source == .local && snapshot?.ownershipVerified == true && changeCount == 0 && !isBusy
    }
    func restoreImportedPlist() async {
        guard canRestoreImportedPlist, let imported = snapshot else { return }
        isBusy = true; defer { isBusy = false }
        do {
            let live = try await files.loadDevice()
            let restored = try await files.restoreVerifiedImport(imported, expected: live)
            let changed = !restored.document.matches(live.document)
            accept(restored); needsRestart = needsRestart || changed
            status = "Changes verified on device"
            message = changed ? L("Backup restored and verified.") + " " + L("Some changes require a device restart.")
                : L("This backup already matches the device. No changes were made.")
            log("[restore] Verified imported document restored")
            await reloadBackups()
        } catch { failed(error); await reloadBackups() }
    }

    func discardImport(_ offer: PlistImportOffer) {
        if let (inbox, entry) = offer.sharedSource {
            do { try inbox.acknowledge(entry) }
            catch { log("[share] Inbox cleanup failed") }
        }
    }

    func stage(_ draft: FieldDraft) throws {
        // Imported plist keys may legitimately contain surrounding whitespace
        // or be empty. Editing their values must not rename those existing keys.
        let preservesKey = draft.originalKey == draft.key && working?.extra[draft.key] != nil
        let key = preservesKey ? draft.key : draft.key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard preservesKey || !key.isEmpty else { throw GestaltFailure("Enter a field key.") }
        guard var doc = working else { throw GestaltFailure("Load a document first.") }
        if draft.originalKey != key && doc.extra[key] != nil { throw GestaltFailure("That key already exists. Edit the existing field instead.") }
        let value = try draft.parsedValue()
        if let originalKey = draft.originalKey, originalKey != key { doc.set(nil, for: originalKey) }
        doc.set(value, for: key); working = doc
        // Explicit field edits take precedence: discard presets that would overwrite the key.
        let changedKeys = Set([key, draft.originalKey].compactMap { $0 })
        for capability in Capability.all where !changedKeys.isDisjoint(with: capability.keys) { choices[capability.id] = .keep }
        if !changedKeys.isDisjoint(with: [GestaltKeys.regionCode, GestaltKeys.regionInfo, GestaltKeys.legacyRegionInfo]) { regionID = "keep"; regionCodeID = "keep" }
        resetLayoutPresets(overriddenBy: changedKeys)
        if changedKeys.contains(GestaltKeys.modelNumber) { modelID = "keep" }
        if !changedKeys.isDisjoint(with: [GestaltKeys.artwork, "Z/dqyWS6OZTRy10UcmUAhw", "bbtR9jQx50Fv5Af/affNtA"]) { changesName = false }
    }
    func removeField(_ key: String) {
        working?.set(nil, for: key)
        for capability in Capability.all where capability.keys.contains(key) { choices[capability.id] = .keep }
        if [GestaltKeys.regionCode, GestaltKeys.regionInfo, GestaltKeys.legacyRegionInfo].contains(key) { regionID = "keep"; regionCodeID = "keep" }
        resetLayoutPresets(overriddenBy: [key])
        if key == GestaltKeys.modelNumber { modelID = "keep" }
        if [GestaltKeys.artwork, "Z/dqyWS6OZTRy10UcmUAhw", "bbtR9jQx50Fv5Af/affNtA"].contains(key) { changesName = false }
    }

    private func resetLayoutPresets(overriddenBy keys: Set<String>) {
        // A subtype preset writes both the artwork member and the capability
        // flag. Explicit edits to either field must win over that preset.
        if !keys.isDisjoint(with: [GestaltKeys.artwork, "YlEtTtHlNesRBMal1CqRaA"]) { subtype = 0 }
        // Restoring/removing the capability also restores its artwork subtype.
        // Enabling only changes the flag, so it can coexist with artwork edits.
        if keys.contains(GestaltKeys.artwork),
           [.disable, .removeAdded].contains(choices["dynamicIsland"] ?? .keep) {
            choices["dynamicIsland"] = .keep
        }
    }

    func apply() async {
        guard !isBusy, let snapshot, let edited = preview else { return }
        if (changesName || subtype != 0), let error = artworkEditingError { failed(error); return }
        guard changeCount > 0 else { return }
        if changesName && modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { failed(GestaltFailure("Enter a model name before applying.")); return }
        isBusy = true
        defer { isBusy = false }
        do {
            log("[apply] source=\(snapshot.source.rawValue) fields=\(changeCount)")
            logChanges(from: snapshot.document, to: edited, prefix: "[diff] ")
            let absentKeys = Set(Capability.all.filter { choices[$0.id] == .removeAdded }.flatMap(\.keys))
            // Stage 5 orchestration (§3.4): a fresh pre-write backup
            // first, then commit with its record — commit verifies
            // the record covers the pre-write bytes and does not
            // write a second backup.
            let preWriteBackup = try await BackupEngine.createPreWriteBackup(store: files, snapshot: snapshot, reason: "Before applying")
            let result = try await files.commit(edited, expected: snapshot, originallyAbsentKeys: absentKeys, preWriteBackup: preWriteBackup)
            accept(result); needsRestart = result.source == .device
            status = result.source == .device ? "Changes verified on device" : "Local changes saved"
            let changedCacheOption = !DeviceCacheOptions.changes(from: snapshot.document, to: edited).isEmpty
            message = L(result.source == .device
                        ? (changedCacheOption ? "Write verified. Some features require a device restart." : "Write verified. Some features require a device restart.")
                        : "Local changes saved. Export the plist to keep a copy.")
            log(L(status)); await reloadBackups()
        } catch { failed(error); await reloadBackups() }
    }

    func backup() async {
        guard !isBusy, let snapshot else { return }
        isBusy = true; defer { isBusy = false }
        do {
            try await files.backup(snapshot); log(L("Backup saved")); message = L("Backup saved")
            recordOperationEvent(.backupCreated, detail: L("Backup saved"))
            await reloadBackups()
        }
        catch { failed(error) }
    }
    func reloadBackups() async {
        do { backups = try await files.backups() } catch { failed(error) }
    }
    func restore(_ record: BackupRecord) async {
        guard !isBusy, let snapshot else { return }
        guard changeCount == 0 else {
            message = L("Save or discard your current changes before opening another plist.")
            return
        }
        isBusy = true; defer { isBusy = false }
        do {
            let data = try await files.backupData(record)
            let restored = try GestaltDocument(data: data)
            log("[restore] \(record.filename) · \(record.byteCount) bytes · reason=\(record.reason)")
            logChanges(from: snapshot.document, to: restored, prefix: "[restore-diff] ")
            // Stage 5 orchestration (§3.4): a fresh pre-write backup
            // first, then commit with its record.
            let preWriteBackup = try await BackupEngine.createPreWriteBackup(store: files, snapshot: snapshot, reason: "Before restoring")
            let result = try await files.commit(restored, expected: snapshot, restoring: record, preWriteBackup: preWriteBackup)
            let changed = !result.document.matches(snapshot.document)
            accept(result); needsRestart = result.source == .device && (needsRestart || changed)
            message = L(result.source == .device
                        ? (changed ? "Backup restored and verified." : "This backup already matches the device. No changes were made.")
                        : "Backup opened as a local document.")
            log(message ?? ""); await reloadBackups()
        } catch { failed(error); await reloadBackups() }
    }
    /// Restores only the four hardware-identity fields (product type,
    /// hardware board, CPU, model number) from a verified same-device
    /// backup, keeping every other change. This is the Face ID
    /// recovery (upstream GestaltX #128/#146): enabling AI by
    /// spoofing the hardware identity can break Face ID, and this
    /// puts the real hardware back without losing the unlock. The
    /// physical product type and board come from the kernel, not the
    /// cache, so a spoofed cache cannot fake them.
    func restoreHardwareIdentity(from record: BackupRecord? = nil) async {
        guard !isBusy, let before = snapshot else { return }
        guard changeCount == 0 else {
            message = L("Save or discard your current changes before opening another plist.")
            return
        }
        isBusy = true; defer { isBusy = false }
        do {
            let physical = GXCopyPhysicalHardwareIdentity()
            guard let product = physical["hw.machine"], let board = physical["hw.model"] else {
                throw GestaltFailure("This device's hardware identity could not be verified.")
            }
            let result: DocumentSnapshot
            let base: GestaltDocument
            if let record {
                base = before.document
                result = try await files.restoreHardwareIdentity(from: record, expected: before,
                                                                 physicalProduct: product, physicalBoard: board)
            } else {
                // No record: restore from the currently loaded verified
                // import (a local document whose ownership was verified
                // on this device — the same entry point as
                // `restoreImportedPlist`). The live device document is
                // re-read as the restore target.
                guard before.source == .local, before.ownershipVerified else {
                    throw GestaltFailure("A verified original hardware backup matching this device and cache is required.")
                }
                let live = try await files.loadDevice()
                base = live.document
                result = try await files.restoreHardwareIdentity(from: before, expected: live,
                                                                 physicalProduct: product, physicalBoard: board)
            }
            logChanges(from: base, to: result.document, prefix: "[restore-hardware] ")
            let changed = !result.document.matches(base)
            accept(result); needsRestart = result.source == .device && (needsRestart || changed)
            message = L(changed ? "Backup restored and verified." : "This backup already matches the device. No changes were made.")
            log(message ?? ""); await reloadBackups()
        } catch { failed(error); await reloadBackups() }
    }
    /// Clears and rebuilds the MobileGestalt cache to a clean factory
    /// baseline (Erosion-CN's "清除并重建缓存", reimplemented for
    /// LilaShift's backup model). The current device file is backed up
    /// first, the live cache is deleted so iOS regenerates it from
    /// the hardware on restart, and the loaded document is cleared:
    /// the file does not exist again until the restart, so the user
    /// re-reads after restarting.
    func rebuildCache() async {
        guard !isBusy, let before = snapshot else { return }
        guard changeCount == 0 else {
            message = L("Save or discard your current changes before opening another plist.")
            return
        }
        guard before.source == .device else {
            message = L("Only a live device cache can be rebuilt. Read the device first.")
            return
        }
        isBusy = true; defer { isBusy = false }
        do {
            let record = try await files.rebuildCache(expected: before)
            log("[rebuild-cache] \(record.filename) · \(record.byteCount) bytes · reason=\(record.reason)")
            snapshot = nil; working = nil; choices = [:]
            regionID = "keep"; regionCodeID = "keep"; modelID = "keep"; changesName = false; subtype = 0
            userConfirmedUnverifiedAICombination = false
            cacheOptionChoice = .keep; wapiChoice = .keep
            modelName = ""
            needsRestart = true
            message = L("Cache rebuilt. Restart the device to finish.")
            log(message ?? "")
            await reloadBackups()
        } catch { failed(error); await reloadBackups() }
    }
    func openBackup(_ record: BackupRecord) async {
        guard !isBusy else { return }
        guard changeCount == 0 else {
            message = L("Save or discard your current changes before opening another plist.")
            return
        }
        isBusy = true; defer { isBusy = false }
        do {
            let data = try await files.backupData(record)
            accept(try await files.loadLocal(data: data, name: record.filename, provenance: record.provenance)); status = "Local file opened"
        } catch { failed(error) }
    }
    func deleteBackup(_ record: BackupRecord) async {
        guard !isBusy else { return }
        isBusy = true; defer { isBusy = false }
        do { try await files.deleteBackup(record); await reloadBackups() } catch { failed(error) }
    }
    func exportBackup(_ record: BackupRecord) async -> TemporaryExport? {
        do {
            let data = try await files.backupExportData(record, sealingWith: { try DeviceBoundPlist.seal($0) })
            return try exportData(data, name: record.filename)
        }
        catch { failed(error); return nil }
    }
    func exportDocument() -> TemporaryExport? {
        guard let doc = preview, let snapshot else { return nil }
        do {
            let plain = try doc.encoded()
            let bytes = snapshot.source == .device || snapshot.ownershipVerified ? try DeviceBoundPlist.seal(plain) : plain
            return try exportData(bytes, name: "MobileGestalt-LilaShift.plist")
        }
        catch { failed(error); return nil }
    }
    private func exportData(_ data: Data, name: String) throws -> TemporaryExport {
        try TemporaryExport(data: data, name: name)
    }
}
