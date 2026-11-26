# Security Policy

## Version and report scope

**Status checked 2026-11-27:** the current source is 4.2.1, build `42000002`, prepared as a maintenance update. [v4.2.0](https://github.com/fafa888uk/LilaShift-3.0/releases/tag/v4.2.0) is the most recent published release verified when this record was prepared. See the [4.2.1 verification record](docs/RELEASE_4_2_1.md) for the integrated source and build evidence. Preparing source or passing CI does not publish a release or establish real-device safety.

| Version | Reporting context |
| --- | --- |
| 4.2.1 source / build `42000002` | Include the exact source commit and workflow/build-manifest evidence; integration and real-device verification must be distinguished. |
| Published 4.2.0 / build `42000001` | Source commit `3152fc7c49ccb00f80f97da90666a65fb66a6d89`; include this version when reporting against the published IPA. |
| 3.x and older | Historical versions; identify the exact version and commit. The old support declarations do not establish an ongoing maintenance commitment for these versions. |

Security reports should identify the affected version even when it is not the latest source. This record does not promise a fix deadline or claim that an unverified build is production-safe.

## How to report a vulnerability

**Do not open a public GitHub Issue for a security vulnerability.**

Report it privately to the maintainer (`@steam8871`) via GitHub:

1. Open a **private** vulnerability report on the repository
   (GitHub → Security → Report a vulnerability), or
2. If private reports are unavailable, open an issue titled
   "Security report — please contact me privately" with **no details**,
   and wait for the maintainer to reach out.

Include in the private report:

- what the vulnerability is and what it affects (e.g. backup integrity,
  plist import, App Group handling, write path);
- steps to reproduce (without personal data);
- the LilaShift version, build number, exact source commit and iOS version; include the workflow URL or build manifest when available;
- the impact you believe it has, and any suggested fix.

## What happens next

- The maintainer will acknowledge the report and assess it.
- Confirmed issues are fixed on the branch, covered by a regression test
  where possible, and disclosed in the CHANGELOG entry for the release that
  carries the fix.
- Do not disclose the vulnerability publicly until a fix is released or the
  maintainer agrees on a disclosure date.
- There is no bug bounty.

## Scope notes

The following are **known design limits, not vulnerabilities** — please do not
report them as security issues:

- LilaShift relies on an unpatched iOS sandbox-escape vulnerability
  (`worse_query`). Apple may close it in a future update; that is a
  compatibility risk, not a vulnerability in LilaShift.
- Restoring a backup returns the values the app recorded; if a value was
  already changed before the app's first backup, the backup contains the
  already-changed value. This is documented in
  `docs/BACKUP_RESTORE_ZH-CN.md`.
- The app can only modify MobileGestalt flags on a device it runs on with
  the user's consent; it cannot add hardware (e.g. an eSIM chip).

## Hardening already in place

- In-place writes (never pre-truncate, `F_FULLFSYNC`, full read-back
  verification, in-place rollback on failure).
- Backups verified against recorded size and SHA-256 digest before reuse;
  restores reject incompatible `CacheUUID` / `CacheVersion` / `CacheData`
  length before any write.
- Shared plist imports reject FIFOs, sockets, directories and symlinks;
  inbox scans open files with `O_NOFOLLOW` and require a regular file
  descriptor.
- Device identity changes are rejected before system writes; exports of
  verified device backups carry device-bound proof whose key stays in the
  device-only Keychain and is never included in the file.
- License compliance is enforced by `scripts/check-licenses.py` and the
  Check Licenses workflow (`.github/workflows/check-licenses.yml`).

## Dependency and build provenance

4.2.1 pins ZIPFoundation 0.9.21 (`e7048f0569f0ba37df26f8357f560b9d25e9a284`) to incorporate upstream archive-handling fixes. The app retains its own containment, size and integrity validation. [Upstream release notes](https://github.com/weichsel/ZIPFoundation/releases/tag/0.9.21) describe the dependency changes; they do not substitute for testing this application's integration.

An IPA is accompanied by its SHA-256 checksum and a build manifest recording the checked-out source commit, app/build versions, toolchain and package pins. Ordinary CI has read-only repository access. Draft publication is a separate manual workflow, targeted at the compiled source commit; existing tags and release assets are not overwritten.

## Secrets

Never post secrets (Apple ID passwords, certificates, API keys, signing
identities) in issues, pull requests, or chat. If you believe a secret has
been exposed in this repository, report it privately as above so it can be
revoked and removed.
