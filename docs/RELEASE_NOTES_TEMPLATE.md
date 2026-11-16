# LilaShift Release Notes Template / 发布说明模板

> How to use: copy this file's body into the GitHub Release notes when
> publishing. Fill every `[placeholder]`; delete any section that does not
> apply. Never claim real-device verification, a test result, a timing, or a
> screenshot that does not exist. The draft is created by the Prepare Draft
> Release workflow (`.github/workflows/prepare-release.yml`, manual dispatch
> only) and is **never published automatically** — publishing is a human decision.
>
> 使用方法：发布时把正文复制到 GitHub Release 说明里，填好每个 `[占位符]`，
> 不适用的小节删掉。不要声称不存在的真机验证、测试结果、耗时或截图。
> 草稿由 Prepare Draft Release 工作流（`.github/workflows/prepare-release.yml`，
> 仅手动触发）创建，**绝不自动发布**——发布由人工决定。

---

# LilaShift [版本号，如 3.0.0-rc.1] · 紫序

> **[Pre-release / 预发布 | Stable / 稳定版]**（二选一，删掉另一个）
> Built from branch `[分支名]` at commit `[完整提交 SHA]`.
> In-app version `[App 内版本号]` (build `[build 号]`); IPA: `[IPA 文件名]`.
> 由 `[分支名]` 分支构建，提交 `[完整提交 SHA]`。
> App 内版本 `[App 内版本号]`（build `[build 号]`），IPA 文件 `[IPA 文件名]`。

## Download / 下载

- IPA: `[LilaShift_<版本>.ipa]`（见本发布页附件）
- SHA-256: `[发布清单里的 SHA-256，逐字粘贴]`
- Minimum iOS / 最低系统：`[如 iOS 26.0]`；本机 MobileGestalt 访问需要
  iOS / iPadOS 27.x

## What is verified / 验证情况

- [ ] CI 构建通过（Build LilaShift IPA run `[链接]`）
- [ ] Swift 单元测试通过（Run Swift Tests run `[链接]`）
- [ ] 许可证检查通过（Check Licenses run `[链接]`）
- [ ] 真机安装验证：`[已验证：机型 + 系统版本 / 未验证]`
- [ ] eSIM 开通验证：`[已验证 / 未验证]`
- [ ] Apple Intelligence 开通验证：`[已验证 / 未验证]`
- [ ] 还原验证：`[已验证 / 未验证]`

> 未验证的项必须如实写“未验证”，不得删除本节来掩盖。

## What's new / 新增

- `[一条写一件事，写清改了什么、谁能用]`
- `[…]`

## Fixed / 修复

- `[问题描述 + 修复提交，如 7020964]`
- `[…]`

## Removed / 移除

- `[如：NeoSpring respring 实现因许可证原因移除，改为手动重启提示]`

## Known issues / 已知问题

- `[已知问题 + 影响范围 +  workaround（如有）]`
- `[…]`

## Compatibility / 兼容性

- 支持本机访问：iOS / iPadOS 27.x；最低可安装 iOS 26.0（26.x 不支持本机访问）。
- eSIM 需要 eUICC 硬件；Apple Intelligence 取决于硬件、系统与苹果服务。
- 系统更新可能还原改动；升级前请先确认兼容性。
- 完整说明：`docs/COMPATIBILITY_ZH-CN.md`

## Install / 安装

一步一步教程：`docs/INSTALL_ZH-CN.md`（简体中文）。
不要向第三方签名服务购买证书，不要把 Apple ID 密码告诉任何人。

## Backup first / 先备份

应用前请备份（整机备份 + App 自动备份）。还原只会写回 App 记录的原值，
不等于真正的出厂状态。详见 `docs/BACKUP_RESTORE_ZH-CN.md`。

## Feedback / 反馈

- Bug 与功能建议：[GitHub Issues](https://github.com/fafa888uk/LilaShift-3.0/issues)
- 更新通知：Telegram 更新频道 [LilaShift 紫序 · 更新公告](https://t.me/LilaShiftUpdates)
  （频道，只发公告，不是讨论群）
- 反馈时不要贴序列号、UDID、IMEI、Apple ID、账号密钥或含个人标识的完整日志。

## Open source / 开源

- Upstream: [huamidev/GestaltX](https://github.com/huamidev/GestaltX) v1.0.7
- Maintainer: @steam8871
- License: GNU GPL v3.0（`LICENSE`）
- 逐项来源：`docs/OPEN_SOURCE_REFERENCES.md`；
  逐功能来源：`docs/FEATURE_ORIGIN_MATRIX.md`

## Disclaimer / 免责声明

非官方修改版，与苹果公司及上游作者无关，仅供安全研究与学习交流，
请仅在本人持有或已获授权的设备上使用。修改 MobileGestalt 可能导致
系统不稳定，严重时需要恢复设备；能力开关不保证功能可用。
