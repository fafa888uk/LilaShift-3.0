LilaShift — Third-Party Notices
Based on GestaltX by huamidev
Copyright (C) 2026 huamidev
https://github.com/huamidev

LilaShift is the enhanced version of GestaltX, maintained by @steam8871
(https://github.com/fafa888uk/LilaShift-3.0). The maintainer role covers
the LilaShift enhancements only: all upstream GestaltX work remains
attributed to its author, huamidev, below.

LilaShift is licensed under the GNU General Public License version 3.
The complete GPL v3 text is included with the app
(GestaltX/Licenses/GestaltX-GPL-3.0.txt) and in LICENSE at the repository
root. No warranty is provided.

How to read this file: each entry states how the material is used —
bundled code (shipped verbatim), adapted code (reworked from upstream),
reused data (values transcribed, code reimplemented), design reference
(ideas reimplemented, no code copied), or research reference (key names
and workflows cross-checked, no code or data copied). Only bundled and
adapted entries ship third-party code in the app.

1. GestaltX — upstream application baseline (bundled code, GPL-3.0)
Author: huamidev — https://github.com/huami1314/GestaltX
Historical repository URL: https://github.com/huamidev/GestaltX
License: GNU GPL v3; full text: GestaltX-GPL-3.0.txt (identical to LICENSE).
LilaShift originated from the GestaltX 1.0.7 baseline (upstream main
c60519c): the MobileGestalt editor, presets, backups, transactions,
staging model and interface. Selected fixes through GestaltX v1.1.1
(f34d5a7271c14e540edb58e328dc9c06f8f3368f), including the App Audio
Library, were adapted into LilaShift before 4.2.0. The complete v1.1.1
pairing/device-console and notification-capture stack is not bundled.
The upstream repository, now huami1314/GestaltX, was checked at main
311f78999d9f5f062f7e3b4c6374684782be5382 on 2026-11-27; a source review
does not imply that every upstream feature has been ported.

LilaShift 4.x adds China Unlock, a dashboard, a feature catalog,
compatibility and version checks, backup/restore engines, diagnostics
and the LilaShift branding. These enhancements are developed in this
repository on the same GPL-3.0 terms. The provisioned App Group
identifier remains group.com.huami.gestultx.

2. worse_query (bundled code, GPL-3.0-or-later)
Author: Taj C (forcequit / forcequitOS)
Copyright (C) 2026 Taj C (forcequit)
Source: https://github.com/forcequitOS/worse_query
License: GPL-3.0-or-later, as stated in the source-file notices.
Included verbatim: GestaltX/worse_query.m and GestaltX/worse_query.h.
The original sandbox-escape implementation and its notices are
preserved. forcequitOS's fsgetpath research is also followed for
container identity discovery (GestaltX/GXCustomizationAccess.m).
GestaltX supplies its own application, document transactions and UI.

3. Ketamine / NeoSpring respring — SUSPENDED and removed 2026-11-14
   (formerly adapted code; see below)
The WebKit respring technique was adapted from Nouvborne/Ketamine
(GPL-3.0) — https://github.com/Nouvborne/Ketamine — whose own
implementation credits rooootdev's NeoSpring project
(https://github.com/rooootdev/neospring). The original WebKit technique
is by neonmodder123 — https://github.com/neonmodder123 — and the Swift
port by skadz108 — https://github.com/skadz108. NeoSpring states no
license anywhere (no LICENSE file, no license header; GitHub API
/license returns 404), so the adaptation had no verifiable
authorization. On 2026-11-14 the user decided (option c) to remove the
implementation: GestaltX/NeoSpringView.swift and all WebKit respring
code were deleted, and the Respring action was replaced by a manual
device-restart prompt that never claims to restart SpringBoard itself.
No respring code ships in this build. Ketamine and NeoSpring remain
credited here as the technique's sources; Ketamine's GPL-3.0 license
text is included in the app (GestaltX-GPL-3.0.txt). If a clearly
sourced, license-compatible implementation is found later, it may be
re-integrated only after independent audit and testing.

4. LCSign (design reference)
Author: huamidev — https://sign.lc
The runtime entitlement-reading approach in
GestaltX/GXEntitlementsReader.m is adapted from LCSign's
LCEntitlementsReader and reimplemented for GestaltX with strict Mach-O
bounds checks and effective SecTask lookup. No LCSign code is bundled.
No public license statement for LCSign was found, so none is asserted
here; it is listed as a design reference from the same author.

5. Erosion-CN (design reference and reused data, GPL-3.0)
Author: Kianuni — https://github.com/Kianuni/Erosion-CN
License: GNU GPL v3; full text: Erosion-GPL-3.0.txt (standard GPL v3 text,
identical to LICENSE). Erosion-CN is a Simplified-Chinese fork of Erosion.
No Erosion-CN code is copied verbatim. Its ideas were reimplemented for
GestaltX, and three data tables were transcribed value-for-value:
- Design reference, reimplemented: the Apple Intelligence readiness
  checkup idea (GestaltX/AIReadinessCheckup.swift, adapted from
  Erosion-CN's AppleIntelligenceCheckupCard); the in-place device-plist
  writer idea (GestaltX/DevicePlistWriter.swift, adapted from Erosion-CN's
  `writeFileAtomically` — the name only; our writer is an in-place pwrite
  writer with no atomicity claim, see its header); the `__cfstring` walk for CacheUUID discovery
  (GestaltX/GXMobileGestaltImage.m, adapted from Erosion-CN's MGImageReader);
  the clear-and-rebuild-cache mechanism (GestaltX/GestaltDocument.swift
  `rebuildCache`, adapted from Erosion-CN's `mgExecuteCleanCacheRebuild` —
  backup first, then delete the live cache so iOS regenerates it from the
  hardware on restart).
- Reused data, transcribed: the US regulatory-model A-number pairs in
  GestaltX/USRegulatoryModelMapping.swift (from Erosion-CN's
  `usRegulatoryModelNumber`); the native Apple Intelligence device list in
  GestaltX/DeviceAIEligibility.swift (from Erosion-CN's `isAppleIntellHD`);
  the native Audio Intelligence / Personal Translator slot baselines in
  GestaltX/DeviceAIEligibility.swift, taken from Erosion-CN's live device
  probes (iPhone 18 Pro Max iPhone19,7 and iPhone 15 Pro Max iPhone16,2,
  iOS 27); the 56 MobileGestalt keys in GestaltX/MGKeysTable.swift (from
  Erosion-CN's `MGCacheLayout.swift`, transcribed value-for-value with the
  upstream line number on each key — the data comes from Erosion-CN, not
  from MGKeys, despite the file name). Erosion-CN's own note warning that a full-US mapping can
  conflict on CN dual-physical-SIM + eSIM hardware is followed in
  GestaltX/Capabilities.swift (Full US stays an explicit opt-in).
- Design reference, reimplemented (LilaShift 3.0 MEDIUM port): the
  fake-supervision residue audit and cleanup (GestaltX/SupervisionAudit.swift,
  from Erosion-CN's ConfigView — deletes only a residue file, never a
  genuine MDM profile); the read-only battery-health and thermal telemetry
  reader (GestaltX/PowerTelemetry.swift, from Erosion-CN's PowerTelemetryView
  — APFS clonefile snapshot of CurrentPowerlog.PLSQL, never written); the
  read-only crash-diagnostics reader (GestaltX/CrashDiagnostics.swift, from
  Erosion-CN's CrashDiagnosticsView — parses .ips reports, never edits a
  system log); the .sgmodule / Stash rule generator and Surge injector
  (GestaltX/ProxyRuleGenerator.swift, GestaltX/ProxyRuleInjector.swift, from
  Erosion-CN's AppGroupHubView — writes one module file into a detected
  proxy client's own AppGroup container only); the AppGroup discovery and
  read-only container browser plus Safari bookmark export
  (GestaltX/AppGroupBrowser.swift, from Erosion-CN's AppGroupHubView —
  group identity read from the container xattr or metadata plist, never
  inferred from a name). The shared container-access and snapshot helpers
  (GestaltX/ContainerAccess.swift, GestaltX/SQLiteSnapshotHelper.swift)
  follow Erosion-CN's WorseQuery.grantAccess and SQLiteSnapshotHelper.
- Design reference, reimplemented (LilaShift 3.0 LOW port): the
  lock-screen asset tag (GestaltX/AssetTag.swift, from Erosion-CN's
  `ConfigView`); the Phone dialer keypad skin (GestaltX/DialerSkin.swift,
  from Erosion-CN's `KeypadManager`/`KeypadView`); the on-device AI model
  cache probe (GestaltX/ModelCacheProbe.swift, from Erosion-CN's
  `VoiceMemosAIView.probeAIModelCaches`); the lossless Voice Memos audio
  export (GestaltX/VoiceMemoExport.swift, from Erosion-CN's
  `VoiceMemosAIView`); the four-microphone phone list for spatial audio
  recording (GestaltX/LilaIntelligence.swift, from Erosion-CN's
  `GestaltHelpers.fourMicPhones`) and the MGCacheLayout key references in
  the same file's capability sources (from Erosion-CN's `MGCacheLayout.swift`).
Because LilaShift is itself GPL-3.0, this reuse stays under the same
license; the attribution above records where the data came from.
Upstream review on 2026-11-27: Erosion-CN v1.0.7 / main
094df45ddaedb044385ada4a4bf0f22e6a6252cb. Its recent ad-cache blocker,
whitelist and legacy-battery-toggle changes are separate features not
bundled in LilaShift. The referenced MGCacheLayout and read-only
power/crash/SQLite helper files had no commits after 2026-11-13.
This review does not expand the application's device/OS support.

6. Erosion (design reference, GPL-3.0)
Author: lunginspector / jailbreak.party and contributors
Source: https://github.com/jailbreakdotparty/Erosion
License: GNU GPL v3; full text: Erosion-GPL-3.0.txt.
Reference for .tendies descriptor layouts and PosterBoard targets
(GestaltX/CustomizationThemes.swift, GestaltX/GXCustomizationAccess.m).
No Erosion code is copied. GestaltX adds its own native interface,
bounded archive validation, runtime container identity checks, isolated
wallpaper ownership records, verified writes and original-file recovery.

7. Gester (design reference, MIT)
Author: sasobhabha; copyright (c) 2026 KAMUI contributors
Source: https://github.com/sasobhabha/Gester
License: MIT License; full text: Gester-MIT.txt.
Reference for PosterBoard descriptor providers, identifier regeneration
and the PosterBoard refresh flag (`PBF_RESET_FILE_PROTECTIONS`,
GestaltX/CustomizationStore.swift). No Gester code is copied; only key
names and descriptor conventions are followed.

8. ZIPFoundation 0.9.21 (bundled library, MIT)
Author: Thomas Zoechling
Source: https://github.com/weichsel/ZIPFoundation
License: MIT License; full text: ZIPFoundation-MIT.txt.
Linked as a Swift Package (exact version 0.9.21) and used for ZIP archive
reading and decompression (GestaltX/CustomizationFiles.swift), pinned
to commit e7048f0569f0ba37df26f8357f560b9d25e9a284. The 0.9.21 release
fixes archive parsing, memory handling and symlink-containment issues.
LilaShift retains its own path, symlink, size and CRC guards.
No wallpaper theme assets are bundled.

9. Primer Octicons (bundled asset, MIT)
Author: GitHub Inc.
Project: https://github.com/primer/octicons
Source: https://raw.githubusercontent.com/primer/octicons/main/icons/mark-github-16.svg
License: MIT License; full text: Primer-Octicons-MIT.txt.
The GitHub mark SVG is bundled as
GestaltX/Assets.xcassets/GitHubMark.imageset/GitHubMark.svg and used as
the GitHub icon on the About page. GitHub names and marks remain GitHub
trademarks.

10. Data sources and research/workflow references
MGKeys supplies the reused name/version metadata explicitly identified
below. The other entries are research references: their application
code and assets are not bundled. LilaShift implements its own preset
catalog, plist model, backups, transactions and interface. Each upstream
retains its own license and copyright. No code from the AGPL-licensed
projects below has been ported.
- PoomSmart/MGKeys (MIT): https://github.com/PoomSmart/MGKeys
  Public MobileGestalt key mappings cross-checked
  (GestaltX/Capabilities.swift). The MGDatabase base table
  (GestaltX/MGDatabaseSeed.swift, iOS 27.2 baseline, master
  db9cf77f) transcribes the readable names and iOS version ranges
  from mapping-gestalt.h and keys_versions.py; 77 used keys are seeded,
  and the full upstream table is not bundled. The reviewed master
  db9cf77fa9d5330070b3dcb73fc1fd6a271fc421 remains current as of
  2026-11-27. The MIT copyright and license for this reused metadata
  are reproduced in full after the research-reference list.
- leminlimez/Nugget (AGPL-3.0): https://github.com/leminlimez/Nugget
  Key mappings cross-checked; no code ported.
- rooootdev/mond (AGPL-3.0): https://github.com/rooootdev/mond
  Key mappings cross-checked; no code ported.
- frs0n/GestaltEdit (GNU GPL v3.0 or later):
  https://github.com/frs0n/GestaltEdit
  Workflow reference only; no code included. License history verified
  2026-11-14: MIT at first release (2026-08-11), PolyForm Noncommercial
  1.0.0 (2026-08-20), then GPL v3 (2026-11-09, commit ed8192e, when the
  project adopted GPL-licensed worse_query). The earlier PolyForm
  statement in this file was outdated and is corrected here.
- kolbicz/WQFiles (GPL-3.0): https://github.com/kolbicz/WQFiles
  LaunchServices database discovery lookup researched
  (GestaltX/GXLaunchServicesDatabase.m); independently implemented,
  no code copied. License: GNU GPL v3; full text: GestaltX-GPL-3.0.txt.
  Not shipped in the IPA.


MGKeys license (source: PoomSmart/MGKeys, revision db9cf77fa9d5330070b3dcb73fc1fd6a271fc421):
MIT License

Copyright (c) 2020 - 2026 PoomSmart

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

11. Test and build tools (not shipped in the app)
These tools are used to test or build LilaShift; their code is not
linked into the IPA and their license texts are not bundled in the
app. Each upstream retains its own license and copyright.
- pointfreeco/swift-snapshot-testing (MIT):
  https://github.com/pointfreeco/swift-snapshot-testing
  Snapshot tests for the key SwiftUI cards (GestaltXTests,
  ViewSnapshotTests). Pinned as an exact Swift Package dependency
  (1.19.7, test target only). License: MIT License, Copyright (c) 2019
  Point-Free, Inc. Not shipped in the IPA. The resolved dependency graph
  also pins swift-custom-dump 1.7.3, swift-issue-reporting 2.1.2 and
  swift-syntax 604.0.0; these remain testing/build dependencies and are
  not added as app target products.
- realm/SwiftLint (MIT):
  https://github.com/realm/SwiftLint
  Swift style and static checks, run in CI from .swiftlint.yml
  (minimal rule set). Not shipped in the IPA.

12. LilaShift 5.0.0 — Wave 1 additions (2026-11-28)
Wave 1 adds six new diagnostics/audit features (W1 device diagnostics,
W2 structured log, W3 IPA security audit, W4 MG key table, W5 network
probe, W6 file browser). The sources below were audited 2026-11-28;
no upstream source file was copied verbatim into this repository —
mechanisms were reimplemented in LilaShift's own Swift, and data tables
were transcribed or regenerated by LilaShift's own generators. Each
entry states the license and what was (and was not) taken.

- devicekit/DeviceKit (MIT, 5.10.0): https://github.com/devicekit/DeviceKit
  Identifier-to-model-name mapping (hw.machine strings such as
  iPhone18,4 → "iPhone Air") and per-model screen facts (diagonal,
  PPI, pixel resolution) transcribed into GestaltX/DeviceDiagnostics.swift
  (DeviceKitModelTable), iPhone family only (iPhone 6 through iPhone 18
  Pro Max). No DeviceKit source code was copied; live readings (screen
  bounds/scale, biometrics, Low Power Mode, brightness, disk capacity)
  use public iOS APIs directly, and no DeviceKit dependency was added.
  License: MIT License; full text: DeviceKit-MIT.txt.
- Kianuni/WQGuard (MIT, v1.3.6, commit 307cf19f37864fa45bd1216bcd2ac908e92a9435):
  https://github.com/Kianuni/WQGuard
  Reimplemented design of the Mach-O parser (fat-binary slice cap,
  64-bit bounds checks, arm64/arm64e), CSBlob parser (SuperBlob magic,
  Slot 5 XML + Slot 7 DER), IPA package scanner (ZIP/ZIP64 validation,
  sandboxed extraction, Zip-Slip interception), threat catalog (rule
  IDs and pins, four-level verdict) and CVE radar structure — in
  GestaltX/IPAAuditMachO.swift, IPAAuditCSBlob.swift,
  IPAAuditScanner.swift, IPAAuditThreatCatalog.swift and
  IPAAuditCVE.swift. All 13 CVE radar CVSS scores and fix versions
  were re-verified against NVD / Apple security advisories; upstream
  scores were not used. Not ported: installed-app inventory engines,
  the lockdownd protocol stack, CSStore2/MCM forensics, proxy-client
  shields, wqguard-cli, CMS certificate-chain validation.
  License: MIT License; full text: WQGuard-MIT.txt.
- GoldensHQ/worstgestalt (GPL-3.0 — not AGPL): https://github.com/GoldensHQ/worstgestalt
  Author: awesomenull; the worse_query escape chain is credited to
  Taj C / forcequitOS (see the upstream README "Licenses" section).
  Key-table data only. The 943-key table in GestaltX/AppleWikiKeyTable.swift
  was regenerated by LilaShift's own generator
  (scripts/generate_apple_wiki_key_table.py) from The Apple Wiki and
  verified key-by-key against upstream GestaltKeyMap.swift (943 keys,
  0 added, 0 missing). Not ported: preset pools (AGPL-sourced per
  upstream README), respring, device spoofing, bad_query backend.
  License: GNU GPL v3; full text: GestaltX-GPL-3.0.txt.
- The Apple Wiki — List of MobileGestalt keys (CC BY-SA 4.0):
  https://theapplewiki.com/wiki/List_of_MobileGestalt_keys
  Human-readable names for all 943 keys and English descriptions
  where the page provides them (671 keys; the other 272 have no
  description on the page and none was invented). Share-alike applies:
  redistributing this table requires keeping The Apple Wiki
  attribution and the CC BY-SA 4.0 statement under the same license.
- ahmadrezaei/ip-tools (MIT, main 6ea8045ba0efc40ff6168e49ddbe07338128cf60):
  https://github.com/ahmadrezaei/ip-tools
  Design of the NetCore layer reimplemented in GestaltX/W5NetworkProbe.swift:
  the ICMP echo codec (RFC 792 / RFC 4443, RFC 1071 checksum),
  unprivileged ICMP datagram socket, pinger/tracer structure and
  statistics, and the RIPEstat endpoints used (whats-my-ip,
  network-info, as-overview). No file was copied verbatim; the App
  target, BGP AS-path graph, WhoisFeature and SwiftUI views were not
  taken. Whether the unprivileged ICMP socket works inside the iOS
  27.x sandbox still needs a real-device check; a socket failure is
  reported honestly. License: MIT License; full text: ip-tools-MIT.txt.
- gewill/PingKit (MIT, design reference only — no code copied):
  https://github.com/gewill/PingKit
  The failed-send-counts-as-loss rule (adopted as .error samples in
  W5Pinger) and the local-network privacy-prompt / backgrounding notes.
  License: MIT License — see https://github.com/gewill/PingKit/blob/main/LICENSE.
- RIPEstat Data API (online data source, no code): https://stat.ripe.net/data
  Egress ASN lookup (whats-my-ip, network-info, as-overview). BGP data
  © RIPE NCC, provided through RIPEstat. Only the public egress IP is
  sent; private / CGNAT / link-local addresses are refused before any
  request. Offline lookups show the offline state with local
  measurements only.
- Kianuni/Erosion-CN (GPL-3.0, v1.0.8; splash-ad paths from v1.0.6/v1.0.7):
  https://github.com/Kianuni/Erosion-CN
  Wave 1 additions — see also entry 5 above. File-browser multi-select
  with batch share / pack-as-ZIP, split file import and recursive
  folder import with a keep-both-or-overwrite choice, streaming copy,
  container-root / metadata / ad-lock / MobileGestalt protection, and
  the splash-ad cache path table (7 apps + Taobao paths) as an
  updatable data table (W6SplashAdPathTable). Every splash-ad path is
  marked pendingVerification ("待核实") — upstream-reported, not yet
  confirmed on LilaShift's own device. Not ported: batch delete,
  ad-cache locking (0555/0444, .erosion_adlock), ad-path clearing, and
  any cross-app cleanup. License: GNU GPL v3; full text: Erosion-GPL-3.0.txt.
- kolbicz/WQFiles (GPL-3.0, main d4aae98ca01d416ea23c60a9fe5c074b5b810798):
  https://github.com/kolbicz/WQFiles
  Wave 1 additions — see also entry 10 above. Read-only cross-app
  file browsing (app list from the LaunchServices database, containers
  through LilaShift's existing ContainerAccess choke point) and
  per-app cache usage statistics. No cleanup was ported (no per-app
  clear, no "clear all"). License: GNU GPL v3; full text: GestaltX-GPL-3.0.txt.

Not used here: Leaflet, gcoord, libimobiledevice, zsign, Feather,
SideStore, AltStore and LiveContainer do not appear in this tree; they
belong to other projects (WLOC web tooling and the LilaShift 2.0
signing/install research) and are deliberately not claimed above. The
app icon is a user-supplied photograph, and the AppMark is the app's own
mark; neither is third-party material.

LilaShift is not affiliated with Apple or any credited project. Upstream
sandbox-escape OS support is not a guarantee that the MobileGestalt
system cache is writable, or that capability flags produce working
hardware features. A verified file write does not prove a feature works.
