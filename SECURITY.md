# Security Policy

## Supported versions

**Release status (2026-11-26):** [v4.2.0](https://github.com/fafa888uk/LilaShift-3.0/releases/tag/v4.2.0) is the latest published release. Please include its exact version, build and source commit when privately reporting an issue. The legacy support table below predates 4.x; its support commitments are not automatically extended to new versions. Maintainers must confirm the updated support policy. Publication alone does not establish real-device safety or compatibility.

| Version | Supported |
| --- | --- |
| 3.0.0-rc.1 (pre-release, `feature/lilashift-3.0-dashboard`) | Yes — security reports accepted, fixes land on the branch first |
| 2.0 / 1.0.7 (LilaShift 2.0) | Yes — critical fixes only |
| Older versions | No — please update |

Pre-releases are supported for reporting, but they are **not stable**: do not
treat a pre-release as production-safe, and do not use it on a device you
cannot afford to restore.

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
- the LilaShift version / commit and the iOS version;
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

## Secrets

Never post secrets (Apple ID passwords, certificates, API keys, signing
identities) in issues, pull requests, or chat. If you believe a secret has
been exposed in this repository, report it privately as above so it can be
revoked and removed.
