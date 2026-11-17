[![LilaShift](GestaltX/Assets.xcassets/AppIcon.appiconset/AppIcon.png)](GestaltX/Assets.xcassets/AppIcon.appiconset/AppIcon.png)

# LilaShift 3.0 · 紫序

**Smart device detection · Feature management · Safe backups · Traceable restore**

[English](README.md) · [简体中文](README_ZH-CN.md)

> **Pre-release: LilaShift 3.0.0-rc.1** — this is a **pre-release, not a stable release**.
> Built from `feature/lilashift-3.0-dashboard` at commit `37c4a368c73ec80654c8b395387abea9a24915f6` (includes fix commit `7020964`).
> In-app version `3.0.0` (build `30000002`) · IPA file `LilaShift_3.0.0.ipa`.
> **Real-device install, eSIM activation, Apple Intelligence activation and restore have NOT been verified for this build: no real-device evidence for this HEAD is in this repository.** See [What is verified](#what-is-verified-and-what-is-not) and `CHANGELOG.md` (Known gaps).

[![Version](https://img.shields.io/badge/version-3.0.0--rc.1%20pre--release-purple)](https://github.com/fafa888uk/LilaShift-3.0/releases/tag/v3.0.0-rc.1)
[![Build LilaShift IPA](https://github.com/fafa888uk/LilaShift-3.0/actions/workflows/build.yml/badge.svg)](https://github.com/fafa888uk/LilaShift-3.0/actions/workflows/build.yml)
[![Run Swift Tests](https://github.com/fafa888uk/LilaShift-3.0/actions/workflows/run-swift-tests.yml/badge.svg)](https://github.com/fafa888uk/LilaShift-3.0/actions/workflows/run-swift-tests.yml)
[![Check Licenses](https://github.com/fafa888uk/LilaShift-3.0/actions/workflows/check-licenses.yml/badge.svg)](https://github.com/fafa888uk/LilaShift-3.0/actions/workflows/check-licenses.yml)
[![SwiftLint](https://github.com/fafa888uk/LilaShift-3.0/actions/workflows/swiftlint.yml/badge.svg)](https://github.com/fafa888uk/LilaShift-3.0/actions/workflows/swiftlint.yml)
[![Platform](https://img.shields.io/badge/iOS-27.x-black?logo=apple)](#compatibility)
[![License](https://img.shields.io/badge/license-GPLv3-blue)](LICENSE)

> **Note on the repository name:** this repo was renamed from `LilaShift-2.0` to `LilaShift-3.0` (and the account from `fafa920q-hue` to `fafa888uk`) on 2026-11-17. Old links redirect to the new location, so no existing links break.

### Quick links

- **Download:** [3.0.0-rc.1 release](https://github.com/fafa888uk/LilaShift-3.0/releases/tag/v3.0.0-rc.1) · [all releases](https://github.com/fafa888uk/LilaShift-3.0/releases)
- **Install guide:** [docs/INSTALL_ZH-CN.md](docs/INSTALL_ZH-CN.md) (Simplified Chinese)
- **User guide:** [docs/USER_GUIDE_ZH-CN.md](docs/USER_GUIDE_ZH-CN.md) · **Compatibility:** [docs/COMPATIBILITY_ZH-CN.md](docs/COMPATIBILITY_ZH-CN.md) · **Backup & restore:** [docs/BACKUP_RESTORE_ZH-CN.md](docs/BACKUP_RESTORE_ZH-CN.md) · **Troubleshooting:** [docs/TROUBLESHOOTING_ZH-CN.md](docs/TROUBLESHOOTING_ZH-CN.md) · **FAQ:** [docs/FAQ_ZH-CN.md](docs/FAQ_ZH-CN.md)
- **Announcements:** [Telegram channel](https://t.me/LilaShiftUpdates) (announcements only — a channel, not a discussion group)
- **Bug reports:** [GitHub Issues](https://github.com/fafa888uk/LilaShift-3.0/issues) — see [COMMUNITY.md](COMMUNITY.md). **Never post serial numbers, UDIDs, account keys, or other personal data in an issue.**

One-tap eSIM, region code, and Apple Intelligence setup for China-model iPhones — the full-source LilaShift 3.0 project, based on upstream [GestaltX](https://github.com/huamidev/GestaltX) v1.0.7.

---

## Table of contents

- [What is verified, and what is not](#what-is-verified-and-what-is-not)
- [What this repository is](#what-this-repository-is)
- [What's new in 3.0.0-rc.1](#whats-new-in-300-rc1)
- [Features](#features)
- [Compatibility](#compatibility)
- [Download](#download)
- [Install](#install)
- [Requirements and caveats](#requirements-and-caveats)
- [Screenshots](#screenshots)
- [FAQ](#frequently-asked-questions)
- [Import a plist](#import-a-plist)
- [Build it yourself](#build-it-yourself)
- [Language support](#language-support)
- [Open source and license](#open-source-and-license)
- [Credits](#credits)
- [Disclaimer](#disclaimer)

---

## What is verified, and what is not

| Area | Status at this pre-release |
|---|---|
| Source builds in CI (`Build LilaShift IPA`) | ✅ Verified by GitHub Actions — see badge above |
| Swift unit tests (`Run Swift Tests`) | ✅ Verified by GitHub Actions — see badge above |
| License / attribution check (`Check Licenses`) | ✅ Verified by GitHub Actions |
| Real-device install of this exact IPA | ⚠️ **Not verified for this build** — no real-device evidence for this HEAD in this repository (see `CHANGELOG.md`, Known gaps) |
| eSIM activation after unlocking | ⚠️ **Not verified for this build** — no real-device evidence for this HEAD in this repository |
| Apple Intelligence actually appearing / working | ⚠️ **Not verified for this build** — no real-device evidence for this HEAD in this repository |
| Restore returning a device to its exact prior state | ⚠️ **Not verified for this build** — no real-device evidence for this HEAD in this repository |

Changing a MobileGestalt flag is **not** the same as the feature working: a flag can read as "on" while the hardware, OS version, or Apple services still say no. Nothing in this README claims every device can unlock everything.

## What this repository is

This is the **full-source project** for LilaShift 3.0 (紫序), the China Unlock enhanced version of GestaltX. The complete modified source lives in this repository — there is no separate patch step; CI builds the IPA straight from this source.

- Based on upstream [huamidev/GestaltX](https://github.com/huamidev/GestaltX) `v1.0.7` (commit `dfd4a7e`, build `11130112`), plus the upstream wallpaper-delete fix in PR #126 (commit `c60519c`).
- The previous patch-based build repository ([fafa888uk/LilaShift](https://github.com/fafa888uk/LilaShift)) is kept as-is and not actively developed.
- LilaShift enhancements maintained by **`@steam8871`**. Upstream GestaltX work remains the work of huamidev.

## What's new in 3.0.0-rc.1

- **LilaShift 3.0 dashboard** — a lightweight home screen with real device read and staged-change status, a 58-item feature catalog across 11 categories (45 preset items + 13 page items), a unified 8-state compatibility model, a history/restore view with confirmation steps, and diagnostic caching that moves file reads and SHA-256 hashing off the render path. See [CHANGELOG.md](CHANGELOG.md).
- **One-tap China Unlock (10 items; 3 on native Apple Intelligence models)** — eSIM switches (`green-tea` off, `not-green-tea` on), region code set to US (`LL`, sales region untouched), and seven Apple Intelligence capabilities, all staged in one tap and reviewed before applying.
  - The eSIM cache layout is verified before staging; if it cannot be verified, the whole eSIM group stops and shows the reason. Region and AI flags can still be set individually.
  - On models with native Apple Intelligence (e.g. iPhone Air), the seven AI items are skipped — the device already has them — so one-tap stages only the 2 eSIM switches + region code.
  - Every apply is automatically backed up and read-back verified. One-tap restore reverts all staged items from the recorded originals.
- **Standalone Siri AI Mode preset** — a single-item toggle that stages only SiriMode = 2, with its own card next to the China AI and eSIM + region presets. Unlike the China AI preset, it is available on native Apple Intelligence models too (an explicit opt-in); it is experimental and usually unnecessary there, since Siri AI already works natively. Unknown models are refused (fail-closed).
- **Light-lavender Liquid Glass redesign** — page background `#F6F3FF`, primary purple `#8652DC`; no large dark backgrounds.
- **Purpose description under every feature** — all presets show a one-line Simplified Chinese purpose description; device requirements and effect details live in the detail view.
- **Author badge and live progress cards** — maintainer `@steam8871` credited in the header and About page; reading/applying show real progress (backup / write / verify / done) driven by the actual operation, never simulated.
- **Open-source compliance** — the About page is a contributor center listing every used or referenced project with author, relationship, technology, license, and source link. Full GPL v3.0 text is bundled in the app. See [docs/OPEN_SOURCE_REFERENCES.md](docs/OPEN_SOURCE_REFERENCES.md) and [docs/FEATURE_ORIGIN_MATRIX.md](docs/FEATURE_ORIGIN_MATRIX.md).
- **Hardened MobileGestalt writes** (design informed by Erosion-CN, no code copied) — in-place writes (never pre-truncate, `F_FULLFSYNC`, full read-back, in-place rollback on failure), runtime dynamic resolution of the eSIM cache layout, a diff preview before applying, a dual-vault backup (including a factory vault that survives uninstall/reinstall), a region-mode choice (region code only, or full US `LL` + `LL/A`), and a 4-factor Apple Intelligence checkup with conflict guards.
- **Respring removed for licensing reasons** — the NeoSpring/Ketamine respring implementation was removed on 2026-11-14 (NeoSpring states no license anywhere). This build has no respring code; the app shows a manual device-restart prompt instead. See `docs/OPEN_SOURCE_REFERENCES.md` §3–§4.
- **LilaShift identity** — the app is named **LilaShift** (中文：紫序), with a cat photo as the app icon.

## Features

| Category | Presets and tools |
|---|---|
| China Unlock | One-tap staging of 10 items (3 on native Apple Intelligence models, where the 7 AI items are skipped): eSIM switches, region code US (`LL`), and seven Apple Intelligence capabilities — reviewed before applying, with eSIM cache-layout verification, automatic backup, read-back verification, and one-tap restore |
| Display | Dynamic Island capability and layout, Always-On Display, AOD Vibrancy, high-luminance AOD, AOD flipbook, HDR photo display, wallpaper parallax, Liquid Glass low-power rendering, experimental PWM and DisplayPort flags |
| Device | Model name, boot/shutdown chime, charge limit, tap to wake, Camera Control settings, Action Button settings, Collision SOS, Audio Mix, Spatial FaceTime audio |
| iPad | Apple Pencil settings, Stage Manager capability, iPad app compatibility |
| Intelligence | Independent region-code options, Apple Intelligence capability flag, on-device Siri, Audio Intelligence, Personal Translator, Photos Clean Up, Handwriting Synthesis, always-listening Hey Siri, Siri AI Mode (standalone single-item toggle, also on native Apple Intelligence models), sales-region options for activation attempts on China-mainland devices |
| Advanced | Apple internal feature flags, system-wide InternalBuild flag with explicit confirmation, internal settings bundle, Security Research Device flag |
| Field editor | Read, search, add, edit, and remove `CacheExtra` fields; local plist import/export; String, Integer, Real, Boolean, Data, Date, Array, and Dictionary values |
| Changes | Automatic reading and manual re-read, staged before/after review, verified writes, per-preset restore |
| Backups | Automatic initial backup before device editing, backup before every write, original-value records; open, export, restore, and delete |
| Logs & restart | Exploit-stage logs and a manual device-restart prompt |

Usually, changing the region code alone is enough to try enabling Apple Intelligence; there is no need to change Sales Region. Selecting **United States** for Region Code sets `RegionCode` to `LL` and keeps the existing sales-region suffix. You can also choose China (Mainland), Hong Kong, Taiwan, Japan, or the United Kingdom. Sales Region and Region Code can be applied together: the sales suffix follows Sales Region, while the code follows Region Code.

> If you previously changed Sales Region, restore your device's original sales region and apply it first.

Disabling a preset or using its Revert button restores the recorded original values and types; keys that were originally absent are removed. If an older change has no original record, use **Remove Added Fields** only when you know those fields were added.

Presets modify capability flags; actual effects depend on the device and OS. China-mainland devices can use the Apple Intelligence and region options to attempt activation; availability also depends on the model, OS version, and Apple services.

Full feature list (Chinese): [docs/FEATURES_ZH-CN.md](docs/FEATURES_ZH-CN.md).

## Compatibility

Supports **iOS / iPadOS 27.x** for on-device MobileGestalt access. **iOS / iPadOS 26.x is not supported** for on-device MobileGestalt access (the app still installs — minimum iOS `26.0` — and local plist editing still works). Powered by [worse_query](https://github.com/forcequitOS/worse_query). SystemGroup access requires iOS 27; available features depend on the device and OS.

Signing requires a certificate and provisioning profile with at least one usable App Group. Sign the app and its embedded share extension with at least one **common App Group** (`group.com.huami.gestultx`), and keep the extension when re-signing. Both processes detect their actual signed App Groups at runtime. Distributed IPAs carry ad-hoc signatures with these entitlements embedded so SideStore and AltStore can detect them when re-signing; they are **not** signed with a developer certificate.

The easiest install needs no signing at all: [LiveContainer](https://github.com/khanhduytran0/LiveContainer) runs the original IPA without re-signing, so the App Group requirement is met without a paid developer account.

Full compatibility table: [docs/COMPATIBILITY_ZH-CN.md](docs/COMPATIBILITY_ZH-CN.md).

## Download

Download the IPA from the [3.0.0-rc.1 release](https://github.com/fafa888uk/LilaShift-3.0/releases/tag/v3.0.0-rc.1) — `LilaShift_3.0.0.ipa` (bundle `com.huami.gestultx`, version `3.0.0`, build `30000002`, minimum iOS `26.0`). The IPA file name comes from the build script (`.github/scripts/build-ipa.sh`): `LilaShift_<version>.ipa`.

> Some users report incomplete downloads with Safari on iOS 27. If the file shows as damaged or cannot be extracted, download it again — several attempts may be needed. Try another browser if it persists. The cause has not been confirmed.

## Install

Full step-by-step tutorial (Chinese): [docs/INSTALL_ZH-CN.md](docs/INSTALL_ZH-CN.md). Short version:

1. Install the IPA with [LiveContainer](https://github.com/khanhduytran0/LiveContainer) (no re-signing needed), or re-sign it with AltStore / SideStore / Sideloadly / a developer certificate — see the tutorial for the differences.
2. Open LilaShift and tap **Read Device** first.
3. Open **China Unlock**, review the staged items (9 on most models; 3 on native Apple Intelligence models), then apply.
4. **Restart the device** after applying — power fully off and back on; a SpringBoard refresh is not enough for eSIM. Then check eSIM and Apple Intelligence in system Settings.
5. To undo everything, use the one-tap restore — it reverts all staged items from the backup.

> Do **not** buy certificates from third-party signing services, and never give anyone your Apple ID password. If a method asks for either, stop.

## Requirements and caveats

- **eSIM hardware is required.** The unlock only flips capability flags; it does not add eSIM hardware to a device that has none.
- **Apple Intelligence depends on hardware and Apple's servers.** Turning the flags on does not guarantee the features appear or work.
- **Carrier and location rules still apply to a stock phone.** Without the unlock, a foreign eSIM cannot be installed while inside mainland China (Apple rule). After the unlock, a user in mainland China can add a foreign eSIM directly — no need to leave the country. Installing one abroad generally needs Location Services on. A Chinese carrier eSIM must be activated at a carrier store in China.
- **System updates may revert the changes.** Re-apply after updating iOS if needed.
- **Do not update iOS blindly.** GestaltX relies on an unpatched iOS sandbox-escape vulnerability (`worse_query`); Apple may close it in a future update. Confirm compatibility before updating if you rely on this tool.
- **Back up before applying.** The app backs up automatically, but a separate device backup is still good practice.
- **"Restore recorded original value" is not "true factory state."** Restore returns the values the app itself recorded before changing them. If a value was already changed before the app's first backup, the backup contains the already-changed value. See [docs/BACKUP_RESTORE_ZH-CN.md](docs/BACKUP_RESTORE_ZH-CN.md).

## Screenshots

No screenshots are included in this pre-release yet. Real screenshots will be added from the actual 3.0.0-rc.1 build on a real device once available — none are fabricated here, and earlier simulator screenshots (showing a "Not read yet" state, not the 10-item China Unlock summary) are not presented as this release.

## Frequently asked questions

### eSIM still doesn't work after unlocking, or "Add eSIM" disappeared

- **iPhone 18 Pro / Pro Max with two physical SIMs in the tray.** These models share one baseband channel between the dual physical slots and the eSIM. If both physical slots are occupied, the baseband can hide "Add eSIM." Fix: remove the SIM tray (empty), apply the unlock, cold restart, add the eSIMs, then reinsert the physical SIM(s).
- **A SpringBoard refresh is not enough for eSIM.** The baseband daemons (`CommCenter`, `ctkd`) do not reload the cache on a SpringBoard refresh. After applying, power the device fully off and back on.
- **Both switches must be on.** The region change and the eSIM change must both be applied; changing only the region code leaves the eSIM hardware lock in place.
- **Never change the model identifier (`ProductType`).** Forcing a China board (e.g. `iPhone19,7`) to a US model breaks baseband checks and hides the eSIM menu entirely.
- **Adding a foreign eSIM inside mainland China is blocked by Apple on a stock phone.** After the unlock, it can be added directly in mainland China — no need to leave the country. (Airplane mode + Wi-Fi through an overseas proxy is only a workaround for the pre-unlock case.)
- **Hardware limits.** Only models with a physical eUICC chip (iPhone Air, iPhone 18 series, etc.) can add eSIMs. Older dual-nano-SIM-only models have no eUICC chip, so the switch only unlocks FaceTime audio and AI region access.

### The preset page and MG Control don't agree

MG Control shows the live `CacheExtra` values; the preset page shows the last read. Tap **Re-read** on the home page first. If they still disagree, the values were written directly (bypassing the preset) — apply the one-tap unlock once to normalize them.

### AI shows 1/7 (or fewer than 7)

Only that many of the 7 AI capability flags are currently on. Open the Apple Intelligence page to see which ones. A change made by an older version persists in the cache until reverted; if it was made before this app's first backup, the backup already contains it.

### I want to restore the original state, but there is no backup

Restore can only return values the app recorded. Check the Backups page for any earlier backup first. If there is none:

- Keys that were **added** (did not exist before) → use **Remove Added Fields**, only for keys you are sure were added.
- Keys that were **modified** → set them back in MG Control. `RegionCode` and the AI flags are `CacheExtra` keys and searchable there. `green-tea` / `not-green-tea` are `CacheData` slots (#383 / #506) and are **not** searchable — set them via the eSIM preset instead (`green-tea` → `true`, `not-green-tea` → `false`).
- Restart the device after restoring.

### The AI menu doesn't appear, or Siri says "something went wrong"

Check that the region code is `LL`, the 7 AI flags are on, and the device has finished downloading the AI models (Wi-Fi + charging, idle for a while). Proxy rules matter: Siri domains (`guzzoni.apple.com`, `*.siri.apple.com`, `dejavu.apple.com`, `sequoia.apple.com`) must go **DIRECT** with a real IP, not through a proxy; AI / Private Cloud Compute domains go through a clean US node. Do not set the system region to United States if you want to keep China Mandarin call screening — set it to Taiwan instead.

If you use a proxy: Siri's core domains must go DIRECT with a real IP, never through a proxy or Fake-IP — `guzzoni.apple.com`, `*.siri.apple.com`, `dejavu.apple.com`, `sequoia.apple.com`, `*.smoot.apple.com` (in Surge, also add `guzzoni.apple.com`, `*.guzzoni.apple.com` and `*.siri.apple.com` to skip-proxy and always-real-ip). AI admission and Private Cloud Compute domains go through a clean US node that supports UDP/QUIC — `gspe1-ssl.ls.apple.com`, `*.issuer.apple.com`, `ropes.apple.com`, `mask-api.icloud.com`, `mask.icloud.com`, `mask-h2.icloud.com`, `*.app.apple.com`, `apple-relay.*`. Do not enable MitM decryption for `gspe1-ssl.ls.apple.com` or `*.smoot.apple.com`. If a generative feature fails with a network error (e.g. Code=32033 or Code=1009), check these rules first. Ready-made rule sets: AppleFlow (github.com/Kianuni/AppleFlow). Source: Erosion-CN FAQ Q3/Q6.

iOS 27.3 limitation: on China-hardware devices (CH/A), iOS 27.3 added an eligibility check that reads the hardware directly (log: `Eligibility returned no CN region policy on a CH region code device`). Even with the region code at LL and all AI flags on, Siri AI and some generative features can be blocked on 27.3; changing MobileGestalt cannot bypass it (Erosion-CN FAQ Q6, situation C). The workaround is to stay on or downgrade to iOS 27.2.x.

### Photos Clean Up works, but high-quality cleanup / extend / reimagine fails

On native-AI iPhones, the factory baseline needs `Personal Translator` slot #266 = `true` and `Audio Intelligence` slot #178 = `false`. Forcing the experimental Audio Intelligence slot can break ModelCatalog asset checks and make high-quality cleanup fail. Turn it off / restore the baseline and try again.

### Reinstalling the app, or the certificate expires

Backups are kept inside the app container — uninstalling the app deletes them. Export your backup before reinstalling or letting the certificate expire.

More questions: [docs/FAQ_ZH-CN.md](docs/FAQ_ZH-CN.md) and [docs/TROUBLESHOOTING_ZH-CN.md](docs/TROUBLESHOOTING_ZH-CN.md).

## Import a plist

In Files or another app, select a MobileGestalt plist, tap **Share**, and choose **LilaShift**. The share extension reads the supplied file and hands it to the app through the shared App Group — return to LilaShift if it does not open automatically. The app checks a device-bound proof from a GestaltX export, or at least two unique identifiers obtained from this device, then asks you to confirm the import. Files that cannot be verified are rejected. Previously imported files are never used as the reference for device identity.

Some original plists contain no unique device identifiers — export a copy from LilaShift on this device first; its verification key stays in the device-only Keychain and is never included in the file.

Shared files are checked at launch and on return to the foreground. Pending edits are preserved until you save or discard them. Confirmed imports open as local documents. **MG Control** supports adding, editing, renaming, and deleting typed keys and values. Use **Restore Imported Plist** to restore a verified file to this device; restoration requires a matching system cache layout and an additional confirmation, backs up the current file, and verifies the write. Restart the device afterward.

## Build it yourself

- **Build LilaShift IPA** (`.github/workflows/build.yml`) — builds the IPA straight from this source on every push to `main` and `feature/lilashift-3.0-dashboard`, pull request, version tag, release, and manual dispatch. The IPA is uploaded as a workflow artifact named `LilaShift-<version>`; tag and release runs also attach it to the matching GitHub release.
- **Run Swift Tests** (`.github/workflows/run-swift-tests.yml`) — runs the XCTest suite on the iOS simulator.
- **Check Licenses** (`.github/workflows/check-licenses.yml`) — runs `scripts/check-licenses.py` on every push that can build an IPA.
- **Prepare Draft Release** (`.github/workflows/prepare-release.yml`, manual dispatch only) — builds the IPA and creates a **draft** GitHub Release; it never publishes automatically.

## Language support

GestaltX follows your iOS language settings, with English as the default and fallback. Persian includes right-to-left layout support.

| Language | Locale |
|---|---|
| English | `en` |
| 简体中文 — Simplified Chinese | `zh-Hans` |
| 繁體中文（台灣）— Traditional Chinese (Taiwan) | `zh-Hant-TW` |
| 繁體中文（香港）— Traditional Chinese (Hong Kong) | `zh-Hant-HK` |
| Tiếng Việt — Vietnamese | `vi` |
| Русский — Russian | `ru` |
| فارسی — Persian | `fa` |
| 한국어 — Korean | `ko` |
| Español — Spanish | `es` |
| 日本語 — Japanese | `ja` |

## Open source and license

This project is distributed under the **GNU General Public License v3.0** — see [LICENSE](LICENSE) (byte-identical to upstream v1.0.7).

- Upstream project: [huamidev/GestaltX](https://github.com/huamidev/GestaltX) (`v1.0.7`, commit `dfd4a7e`, plus PR #126, commit `c60519c`)
- Enhanced version maintainer: `@steam8871`
- Modifications in this build: the China Unlock preset (10 items; 3 on native Apple Intelligence models) and its safety checks, the light-lavender Liquid Glass redesign, one-line purpose descriptions, the author badge and progress cards, the in-app source-repository link, the open-source compliance section, the Erosion-CN-inspired hardening (write path, dynamic layout resolution, diff preview, dual-vault backup, region mode, AI checkup), the LilaShift rebrand, and the cat app icon.
- LilaShift 3.0 additions: the lightweight dashboard, the 58-item feature catalog, the unified compatibility model, the history/restore view, diagnostic caching, and the open-source contributor center (About page) with the per-project source record in `docs/OPEN_SOURCE_REFERENCES.md`. Also: Face ID recovery (restore only the four hardware-identity fields from a verified same-device backup, upstream GestaltX #128/#146, extended to iPhone 16/17/Air), clear-and-rebuild MobileGestalt cache (Erosion-CN mechanism, reimplemented; backup taken first), and a one-click AI baseline fix in the one-tap flow (Personal Translator slot #266 = 1, Audio Intelligence slot #178 = 0, absent AI keys filled).
- The complete corresponding source is in this repository (full source, no patch step).

## Credits

- **huamidev** — GestaltX
- [forcequitOS / Taj C — worse_query](https://github.com/forcequitOS/worse_query)
- [neonmodder123](https://github.com/neonmodder123)
- [skadz108](https://github.com/skadz108)
- [rooootdev — NeoSpring](https://github.com/rooootdev/neospring) (no license stated; respring use suspended and removed 2026-11-14 — see `docs/OPEN_SOURCE_REFERENCES.md`)
- [Nouvborne — Ketamine](https://github.com/Nouvborne/Ketamine)
- [huamidev — LCSign](https://sign.lc)
- [Kianuni — Erosion-CN](https://github.com/Kianuni/Erosion-CN)
- [lunginspector / jailbreak.party — Erosion](https://github.com/jailbreakdotparty/Erosion)
- [sasobhabha — Gester](https://github.com/sasobhabha/Gester)
- [Thomas Zoechling — ZIPFoundation](https://github.com/weichsel/ZIPFoundation)
- [GitHub Inc. — Primer Octicons](https://github.com/primer/octicons)
- [PoomSmart — MGKeys](https://github.com/PoomSmart/MGKeys)
- [leminlimez — Nugget](https://github.com/leminlimez/Nugget) (AGPL-3.0, reference only — no code ported)
- [rooootdev — mond](https://github.com/rooootdev/mond) (AGPL-3.0, reference only — no code ported)
- [frs0n — GestaltEdit](https://github.com/frs0n/GestaltEdit)
- [Point-Free — SnapshotTesting](https://github.com/pointfreeco/swift-snapshot-testing) (test tool, not shipped in the app)
- [Realm — SwiftLint](https://github.com/realm/SwiftLint) (build tool, not shipped in the app)

Full per-project record (license, evidence, relationship, files, IPA inclusion): [docs/OPEN_SOURCE_REFERENCES.md](docs/OPEN_SOURCE_REFERENCES.md). Per-feature origin map: [docs/FEATURE_ORIGIN_MATRIX.md](docs/FEATURE_ORIGIN_MATRIX.md).

## Disclaimer

This is an unofficial modified build, not affiliated with Apple or endorsed by the upstream author. For security research and educational purposes only. Use only on devices you own or are authorized to manage.

Back up your data before making changes. Modifying MobileGestalt may cause system instability or require a device restore. Capability flags do not guarantee features. You are responsible for the changes you apply and the resulting risks.

## License

[GNU GPL v3](LICENSE) · Copyright © 2026 huamidev. China Unlock enhancements maintained by `@steam8871`.
