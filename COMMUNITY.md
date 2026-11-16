# Community

LilaShift (紫序) is the China Unlock enhanced version of GestaltX, maintained
by `@steam8871`, based on upstream [huamidev/GestaltX](https://github.com/huamidev/GestaltX)
v1.0.7. This page explains where to get news, where to ask, and how to report
problems — and where *not* to.

## Official announcement channel (Telegram)

- **LilaShift 紫序 · 更新公告** — https://t.me/LilaShiftUpdates
- This is the official **announcement channel**: release notes, beta notices,
  device compatibility and known issues.
- It is a **channel, not a discussion group**. There is no official discussion
  group, and no other `t.me` link is official. Do not trust download links
  from anywhere else.
- Source, downloads and feedback live on GitHub, not in Telegram.

## Feedback and bug reports (GitHub Issues)

- **Issues:** https://github.com/fafa888uk/LilaShift-3.0/issues
- Use the issue templates:
  - **Bug report** — what happened, what you expected, steps to reproduce,
    LilaShift version (e.g. 3.0.0-rc.1, build 30000002), iOS version, device
    model, install method (LiveContainer / AltStore / SideStore / Sideloadly /
    developer certificate / built from source). Attach a *redacted* log excerpt
    if it helps.
  - **Feature request** — what you want, why, and what device / system it
    applies to. Requests that need hardware the device does not have (e.g.
    adding an eSIM chip by software) will be closed as not possible.
- Before opening an issue, check the docs first:
  [INSTALL_ZH-CN.md](docs/INSTALL_ZH-CN.md),
  [USER_GUIDE_ZH-CN.md](docs/USER_GUIDE_ZH-CN.md),
  [COMPATIBILITY_ZH-CN.md](docs/COMPATIBILITY_ZH-CN.md),
  [BACKUP_RESTORE_ZH-CN.md](docs/BACKUP_RESTORE_ZH-CN.md),
  [TROUBLESHOOTING_ZH-CN.md](docs/TROUBLESHOOTING_ZH-CN.md),
  [FAQ_ZH-CN.md](docs/FAQ_ZH-CN.md).
  Most "eSIM menu disappeared" and "AI menu missing" reports are already
  answered there.
- Be honest about what you observed. "It works on my device" is useful only
  with the device model, iOS version and install method attached.
- Maintainers may close issues that ask for shady certificates, ask for
  someone else's Apple ID password, or request changes to devices the reporter
  does not own.

## Privacy reminder — read before you post

**Never post in an issue, in Telegram, or anywhere public:**

- serial numbers, UDID, IMEI, ECID;
- Apple ID, passwords, verification codes, account keys;
- full logs containing personal identifiers;
- photos of personal documents.

If a log is needed, trim it to the relevant lines and remove identifiers
first. If you posted something sensitive by accident, tell a maintainer
immediately so the comment can be removed.

## Security issues

Do **not** open a public issue for a security vulnerability. See
[SECURITY.md](SECURITY.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). In short: read the open-source
compliance rules first (attribution and license obligations), do not submit
code from a source without a compatible license, and do not bypass CI or
quality gates.

## Code of conduct

- Be specific and evidence-based; no invented success claims.
- Do not ask other users for their Apple ID, passwords, certificates, or
  personal device identifiers.
- Do not advertise paid signing services or "permanent certificate" sellers.
- Maintainers may remove content that violates these rules.
