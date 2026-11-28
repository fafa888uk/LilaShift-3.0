// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// In-app reference table of MobileGestalt keys (A22).
///
/// Every entry names the open-source source it was verified
/// against. No key is guessed: the Erosion-CN rows are the 56 keys
/// in its `MGCacheLayout.swift` (Kianuni, GPL-3.0), the capability
/// rows come from LilaShift's own registry (whose keys were
/// cross-checked against MGKeys, MIT, and upstream GestaltX), and
/// the identity rows are the app's own `GestaltKeys`. Rows are
/// deduplicated by key — a capability row wins over an Erosion-CN
/// row for the same key, because it carries the app's own meaning.
struct MGKeyEntry: Identifiable, Equatable {
    /// The obfuscated MobileGestalt key; also the row identity.
    var id: String { key }
    let name: String
    let key: String
    let meaning: String
    let source: String
    /// Reviewed Simplified Chinese name (`MGKeyChineseNames`), or `nil`
    /// when no reviewer has translated this key yet. Views must show
    /// `MGKeyChineseNames.missingChineseNameLabel` ("暂无中文名") for
    /// `nil`, never a guess.
    let chineseName: String? = nil
    /// Reviewed Simplified Chinese description, or `nil` with `chineseName`.
    let chineseDescription: String? = nil
}

enum MGKeysTable {
    /// The 56 keys in Erosion-CN's `MGCacheLayout.swift`, with the
    /// MobileGestalt question name each key answers and the file
    /// line it was read from.
    static let erosionCNKeys: [(name: String, key: String, question: String, line: Int)] = [
        ("Green Tea", "iyfxmLogGVIaH7aEgqwcIA", "green-tea", 26),
        ("Not Green Tea", "4snMZS8LJkSctKypt2m+xA", "not-green-tea", 27),
        ("WAPI", "hiHut/WR+B9Lx/vd0WyeNg", "wapi (WLAN vs Wi-Fi)", 28),
        ("Audio Mix", "aVL5GE3tx0LSCI/ErfrJGA", "CameracinematicAudioTrackRendering", 31),
        ("Spatial Audio Recording", "X6NGcYcvHmbqlR8hLXASJA", "spatial-audio-recording", 32),
        ("Spatial FaceTime Audio", "/EVOCjM/Nmb2roP5ebtEFA", "spatial-facetime-audio", 33),
        ("Responsive Shutter", "gQDt76Te0SPw7N8oTLrBFw", "ResponsiveShutter", 34),
        ("Hypertension Notifications", "4fh9efw4o1yaFqkXNCXoeA", "HypertensionNotifications", 35),
        ("Apple Intelligence", "A62OafQ85EJAiiqKn4agtg", "DeviceSupportsGenerativeModelSystems", 38),
        ("Photos Clean Up", "XNCjqOupLM/S8fNyxRNQTA", "Photos Clean Up", 39),
        ("Handwriting Synthesis", "YgYIIViDt1kgzyIsIV61vA", "Handwriting Synthesis", 40),
        ("Audio Intelligence", "rb2tKZxlj0Gm2tBmUQSLqQ", "supports-audio-intelligence", 41),
        ("Personal Translator", "M1n2sAqf33NAOgZRGxQYBA", "supports-personal-translator", 42),
        ("Dynamic Island", "YlEtTtHlNesRBMal1CqRaA", "DeviceSupportsDynamicIsland", 45),
        ("Always-On Display", "2OOJf1VhaM7NxfRok3HbWQ", "DeviceSupportsAlwaysOnDisplay", 46),
        ("Always-On Time", "j8/Omm6s1lsmTDFsXjsBfA", "DeviceSupportsAlwaysOnTime", 47),
        ("Always-On Display Vibrancy", "ykpu7qyhqFweVMKtxNylWA", "DeviceSupportsAODVibrancy", 48),
        ("Liquid Glass Low Power", "SAGvsp6O6kAQ4fEfDJpC4Q", "DeviceSupportsLiquidGlassLowPower", 49),
        ("80% Charge Limit", "37NVydb//GP/GrhuTN+exg", "DeviceSupports80ChargeLimit", 50),
        ("Boot Chime", "QHxt+hGLaBPbQJbXiUJX3w", "DeviceSupportsBootChime", 51),
        ("Collision SOS", "HCzWusHQwZDea6nNhaKndw", "DeviceSupportsCollisionSOS", 52),
        ("Pulse Width Maximization", "6IejgN+1Fmu5/QrZFOIeNw", "DeviceSupportsPulseWidthMaximization", 53),
        ("Apple Pencil", "yhHcB0iH0d1XzPO/CFd3ow", "DeviceSupportsApplePencil", 54),
        ("Camera Button", "CwvKxM2cEogD3p+HYgaW0Q", "CameraButtonCapability", 55),
        ("Ringer Button", "cT44WE1EohiwRzhsZ8xEsw", "RingerButtonCapability", 56),
        ("Tap to Wake", "yZf3GTRMGTuwSV/lD7Cagw", "DeviceSupportsTapToWake", 57),
        ("Stage Manager", "qeaj75wk3HF4DwQ8qbIi7g", "DeviceSupportsEnhancedMultitasking", 58),
        ("Regional Camera Shutter Relaxation", "P4ZJVy/zYuLy4ejRKP+0DA", "DeviceSupportsRegionalCameraShutterRelaxation", 61),
        ("Keyboard Mute Preserves Shutter Click", "bGUN8lS6sYzy3xhePubp8A", "KeyboardMutePreservesRegionalShutterClickBehavior", 62),
        ("Keyboard Mute Preserves Shutter Click (Legacy)", "Bim3FC83Te8QX1kfSpqYKQ", "KeyboardMutePreservesRegionalShutterClickBehaviorForLegacyDevices", 63),
        ("Concurrent HPLP Mics", "dI30ovtFUIeLioNQKDMbGQ", "DeviceSupportsConcurrentHPLPMics", 64),
        ("Photos Local Light", "m9ORTKMgu9A+zF+A61Zz5A", "DeviceSupportsPhotosLocalLight", 65),
        ("Tone Mapping", "Lcu6Zck+C/+AMO8qULacDw", "DeviceSupportsToneMapping", 66),
        ("HDR Deferred Processing", "JkZlE8z9YwHjE1hnbMhcgA", "DeviceSupportsHDRDeferredProcessing", 67),
        ("Spatial Over Capture", "SjQQ07G8UacM7E69G7dPbg", "DeviceSupportsSpatialOverCapture", 68),
        ("Stereo Audio Recording", "YlK+0xmxNWhNn/+r8SM8kA", "DeviceSupportsStereoAudioRecording", 69),
        ("P3 Video Recording", "1eBwtCIwbIDdC80wiyzfow", "DeviceSupportsP3ColorspaceVideoRecording", 70),
        ("Touch-Sensitive Camera Control", "lyJZrSDc8J8eQ5Zb7A1Rvw", "DeviceSupportsTouchSensitiveCameraControl", 71),
        ("Hardware Detents", "V9pLLbPQhyb75bbdTioZVw", "DeviceSupportsHardwareDetents", 72),
        ("Camera Haptics", "XriAxQ+JY1z5nt5f3ftXVw", "DeviceSupportsCameraHaptics", 73),
        ("Battery Model Information (Legacy HW)", "Rq0MF/w+gXM66Ii4fkWOzg", "DeviceShowsBatteryModelInformationLegacyHW", 74),
        ("Dynamic End of Charge (Legacy HW)", "nfR1IphTGCaoFNu3NrCtWQ", "DeviceSupportsDynamicEndOfChargeLegacyHW", 75),
        ("High-Luminance Always-On Display", "7brdL5xrEUWnlF9C0kdg5A", "DeviceSupportsHighLuminanceAlwaysOnDisplay", 76),
        ("Always-On Display Flipbook", "aoJSd/MXk7M40NgXTM6x+g", "DeviceSupportsAlwaysOnDisplayFlipbook", 77),
        ("CarPlay 2", "PR+xeEtTAiUN0R25+EYGfw", "DeviceSupportsCarPlay2", 78),
        ("Touch Delivery 120 Hz", "2OK50OGmkXM1ospsh766WQ", "TouchDelivery120Hz", 79),
        ("Hearing Aid Audio Equalization", "SMgTCc2v9AU2ziIHRX8qww", "hearingaid-audio-equalization", 80),
        ("Hearing Aid Low-Energy Audio", "RyXm3yMC4ejlFvwlEI509w", "hearingaid-low-energy-audio", 81),
        ("Hearing Aid Power Reduction", "u3c0R+31Df4SUTHrICQkTg", "hearingaid-power-reduction", 82),
        ("Breathing Disturbances Measurements", "e0HV2blYUDBk/MsMEQACNA", "DeviceSupportsBreathingDisturbancesMeasurements", 83),
        ("US Blood Oxygen", "E4vGMChwcVRKD8hMVxnRvg", "DeviceSupportsUSLegallyCompliantBloodOxygen", 84),
        ("Workout Ultra Mode", "fu+4kyf8VcMBtgbMyJlLtg", "WorkoutUltraMode", 85),
        ("Time in Daylight", "8gVfz9/8R1OtWBBtI0o/+Q", "DeviceSupportsTimeInDaylight", 86),
        ("Siri Hub", "waGD2UTpntjbDXD1r3oALQ", "DeviceSupportsSiriHub", 87),
        ("On-Device Siri", "O/7gbXWA5X2IRPVtDRU+bw", "OnDeviceSiriCapability", 88),
        ("Instruction-Following Model Pruning", "m4xs4mhvxnAopYrApoLDMw", "DeviceSupportsInstructionFollowingPruningModels", 89),
    ]

    /// Device-identity keys the app itself reads (not capabilities).
    static let identityKeys: [(name: String, key: String, meaning: String)] = [
        ("Region Code", GestaltKeys.regionCode, "The device sales region code (e.g. LL)."),
        ("Region Info", GestaltKeys.regionInfo, "Region information record."),
        ("Legacy Region Info", GestaltKeys.legacyRegionInfo, "Legacy region information record."),
        ("Product Type", GestaltKeys.productType, "The device model identifier (e.g. iPhone18,4)."),
        ("Model Number", GestaltKeys.modelNumber, "The device model number."),
        ("Hardware Model", GestaltKeys.hardwareModel, "The hardware board identifier (hw.model)."),
        ("CPU", GestaltKeys.cpu, "The chip (CPU) identifier."),
        ("Siri AI Mode", GestaltKeys.siriMode, "The Siri AI mode value (2 = Siri AI mode on)."),
        ("Launch Artwork", GestaltKeys.artwork, "The launch artwork (splash screen) key."),
    ]

    /// All rows, deduplicated by key and sorted by name.
    /// Capability rows win over Erosion-CN rows for the same key.
    /// Built once: every input is a static table, so the result
    /// never changes. Previously this rebuilt (dedup + sort) on
    /// every access — including every keystroke of a search, since
    /// `matching` reads `all` first.
    ///
    /// This stays the 77 curated rows on purpose: `MGDatabaseSeed`
    /// mirrors it exactly (see `MGDatabaseTests`), so the ~940-key
    /// Apple Wiki table is *not* merged here. It lives in
    /// `appleWikiEntries` and is searched together with `all` by
    /// `matching`, which is the field editor's search entry point.
    static let all: [MGKeyEntry] = {
        var byKey: [String: MGKeyEntry] = [:]
        for (name, key, question, line) in erosionCNKeys {
            byKey[key] = MGKeyEntry(
                name: name, key: key,
                meaning: "MobileGestalt question “\(question)”.",
                source: "Erosion-CN MGCacheLayout.swift:\(line)")
        }
        for (name, key, meaning) in identityKeys {
            byKey[key] = MGKeyEntry(name: name, key: key, meaning: meaning, source: "LilaShift GestaltKeys")
        }
        for capability in Capability.all {
            for key in capability.keys {
                byKey[key] = MGKeyEntry(
                    name: capability.title, key: key,
                    meaning: capability.detail,
                    source: "LilaShift capability “\(capability.id)”")
            }
        }
        return byKey.values
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { withChinese($0) }
    }()

    /// The Apple Wiki rows the curated table does not cover: 878 of the
    /// 943 wiki keys (the other 65 are already curated rows above).
    /// Name is the wiki plain key name; meaning is the wiki English
    /// description, or a plain statement of the key when the wiki has
    /// no description. Sorted by name, like `all`.
    static let appleWikiEntries: [MGKeyEntry] = {
        let curatedKeys = Set(all.map(\.key))
        return AppleWikiKeyTable.names
            .filter { !curatedKeys.contains($0.key) }
            .sorted { $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending }
            .map { key, plainName in
                withChinese(MGKeyEntry(
                    name: plainName, key: key,
                    meaning: AppleWikiKeyTable.descriptions[key]
                        ?? "MobileGestalt key “\(plainName)”.",
                    source: "The Apple Wiki “List of MobileGestalt keys” (CC BY-SA 4.0)"))
            }
    }()

    /// Rows `matching` can return: the curated table plus the Apple
    /// Wiki-only rows (955 in total).
    static var searchableCount: Int { all.count + appleWikiEntries.count }

    /// A row with its reviewed Chinese name and description attached
    /// (when one exists for its key).
    private static func withChinese(_ entry: MGKeyEntry) -> MGKeyEntry {
        MGKeyEntry(
            name: entry.name, key: entry.key,
            meaning: entry.meaning, source: entry.source,
            chineseName: MGKeyChineseNames.chineseName(forKey: entry.key),
            chineseDescription: MGKeyChineseNames.chineseDescription(forKey: entry.key))
    }

    /// Precomputed search text, one entry per searchable row, built
    /// once: the English name, key and meaning, the reviewed Chinese
    /// name and description when they exist, and the Apple Wiki plain
    /// name and description for the key when the wiki knows it. The
    /// label `MGKeyChineseNames.missingChineseNameLabel` is deliberately
    /// *not* in the haystack: "暂无中文名" is a status, not a name, and
    /// searching for it must return nothing.
    private static let searchIndex: [(entry: MGKeyEntry, haystack: String)] = {
        var index: [(entry: MGKeyEntry, haystack: String)] = []
        index.reserveCapacity(all.count + appleWikiEntries.count)
        for entry in all + appleWikiEntries {
            var parts = [entry.name, entry.key, entry.meaning]
            if let chineseName = entry.chineseName { parts.append(chineseName) }
            if let chineseDescription = entry.chineseDescription { parts.append(chineseDescription) }
            if let plainName = AppleWikiKeyTable.plainName(forHashedKey: entry.key) {
                parts.append(plainName)
            }
            if let description = AppleWikiKeyTable.description(forHashedKey: entry.key) {
                parts.append(description)
            }
            let haystack = parts.joined().lowercased().filter { !$0.isWhitespace }
            index.append((entry: entry, haystack: haystack))
        }
        return index
    }()

    /// Rows matching a search string (name, key, meaning, Apple Wiki
    /// plain name or description, or reviewed Chinese name or
    /// description). Whitespace is ignored on both sides, so typing a
    /// camelCase feature name such as "DynamicIsland" finds the
    /// "Dynamic Island" row, and typing "灵动岛" finds it too.
    ///
    /// An empty query returns the 77 curated rows only: that is the
    /// browse list, and `MGDatabaseSeed` mirrors it exactly. A
    /// non-empty query searches the full 955-row index, deduplicated
    /// by key (a curated row wins over the wiki row for the same key).
    static func matching(_ query: String) -> [MGKeyEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return all }
        let squashed = trimmed.lowercased().filter { !$0.isWhitespace }
        return searchIndex.filter { $0.haystack.contains(squashed) }.map(\.entry)
    }
}
