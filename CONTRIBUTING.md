# Contributing to LilaShift

LilaShift (紫序) is the China Unlock enhanced version of GestaltX, maintained
by `@steam8871`, based on upstream [huamidev/GestaltX](https://github.com/huamidev/GestaltX)
v1.0.7 and distributed under the **GNU General Public License v3.0**.
Contributions are welcome — these rules exist because this project modifies
system behavior on real devices and carries strict open-source obligations.

## Before you start

1. Read [docs/OPEN_SOURCE_REFERENCES.md](docs/OPEN_SOURCE_REFERENCES.md) and
   [docs/FEATURE_ORIGIN_MATRIX.md](docs/FEATURE_ORIGIN_MATRIX.md). Every
   feature has a recorded origin; every third-party project has a recorded
   license, relationship and evidence.
2. Read [SECURITY.md](SECURITY.md) before touching the write path, backups,
   plist import, or App Group handling.
3. Check open issues and pull requests so you do not duplicate work.
4. For large changes, open an issue first and describe the plan.

## License and attribution — non-negotiable

- All contributions are licensed under **GPL-3.0**, the same as the project.
  By submitting, you agree your contribution is distributed under GPL-3.0.
- **Do not submit code from a source without a compatible license.**
  - AGPL-3.0 projects (e.g. Nugget, SideStore, LiveContainer, AltStore, mond)
    are **reference only**: study the design, do not port code.
  - Projects with **no license stated** (e.g. NeoSpring) must not be copied
    or adapted at all — the NeoSpring respring implementation was removed
    from this project for exactly this reason (2026-11-14).
  - MIT / BSD / LGPL / GPL-3.0 code may be used only with its license text
    and attribution preserved; record it in `docs/OPEN_SOURCE_REFERENCES.md`
    and `THIRD_PARTY_NOTICES.md`.
- New files that use or adapt third-party code must carry a copyright header
  (SPDX identifier + original source + modification notes), matching the
  convention already used in the 20 normalized files.
- After any change affecting attributions, licenses, or the app version, run
  `python3 scripts/check-licenses.py` — the Check Licenses workflow runs it
  on every IPA-building push and will fail the build otherwise. License
  consistency is also covered by `tests/ThirdPartyNoticesTests.py`.
- Do not remove or weaken existing attributions (huamidev/GestaltX,
  forcequitOS/worse_query, Kianuni/Erosion-CN, PoomSmart/MGKeys, and the rest
  listed in `THIRD_PARTY_NOTICES.md`).

## How to contribute

1. Fork the repository and create a branch from `feature/lilashift-3.0-dashboard`
   (for 3.0 work) or `main` (for anything else).
2. Make focused changes: one concern per pull request.
3. Follow the existing code style; SwiftLint runs on every PR to `main`
   (`.swiftlint.yml` — minimal rule set, only rules the current codebase
   already passes). Keep it green.
4. Add or update tests for behavior changes. The XCTest suite runs via the
   Run Swift Tests workflow (`.github/workflows/run-swift-tests.yml`); a
   green check there means the tests passed, not just that the app compiles.
   Snapshot references are recorded on the first CI run and must be committed
   in a follow-up — see `docs/SNAPSHOT_TESTING.md`.
5. Update docs in the same PR when behavior, compatibility, or install steps
   change: README (EN + ZH-CN), CHANGELOG (EN + ZH-CN), and the relevant
   `docs/*_ZH-CN.md` guide. Do not claim real-device verification, test
   results, timings, or screenshots you do not have.
6. Do not commit secrets, certificates, provisioning profiles, or Apple IDs.
7. Open the pull request against the same branch you branched from, with a
   clear description: what changed, why, how it was tested, and what is
   still unverified.

## What will not be merged

- Code copied from a source without a verifiable compatible license.
- Changes that bypass CI, the license check, or the test suite.
- Changes that weaken backup integrity, write verification, restore safety,
  or plist-import validation.
- Changes that claim a feature works on hardware the device does not have,
  or that present staging / simulator results as real-device verification.
- Merges to `main` and releases are maintainer decisions; pre-releases are
  never published automatically (the Prepare Draft Release workflow creates
  drafts only).

## Release process (maintainers)

1. Bump the version with `python3 scripts/prepare-release.py --version X.Y.Z
   --write-project` and push it, so the IPA and the tag agree.
2. Dispatch the Prepare Draft Release workflow (`.github/workflows/prepare-release.yml`,
   manual dispatch only) with the PR list; it builds the IPA and creates a
   **DRAFT** GitHub Release. It never publishes and fails loudly if the tag
   already exists.
3. Fill the release notes from `docs/RELEASE_NOTES_TEMPLATE.md`, verify the
   IPA SHA-256 against the release manifest, and confirm the verification
   table honestly (unverified items stay "unverified").
4. A human publishes the draft on GitHub. Pre-releases are marked
   **Pre-release** and are never called stable.

## Questions

Open a GitHub Issue (not Telegram — the channel is announcements only):
https://github.com/fafa888uk/LilaShift-3.0/issues
