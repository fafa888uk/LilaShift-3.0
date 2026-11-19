[![LilaShift](GestaltX/Assets.xcassets/AppIcon.appiconset/AppIcon.png)](GestaltX/Assets.xcassets/AppIcon.appiconset/AppIcon.png)

# LilaShift 4.2.0 · 紫序

**智能设备检测 · 功能管理 · 安全备份 · 可追溯恢复**

[English](README.md) · [简体中文](README_ZH-CN.md) · [日本語](README_JA.md)

> **预发布版本：LilaShift 3.0.0-rc.1** —— 这是**预发布版，不是正式稳定版**。
> 基于 `feature/lilashift-3.0-dashboard` 分支构建，提交 `37c4a368c73ec80654c8b395387abea9a24915f6`（包含 fix 提交 `7020964`）。
> App 内版本号 `3.0.0`（构建号 `30000002`），IPA 文件名 `LilaShift_3.0.0.ipa`。
> **真机安装、eSIM 激活、Apple Intelligence 激活与恢复，本版本均未验证：仓库中没有针对此 HEAD 的真机证据。** 详见[已验证内容与未验证内容](#已验证内容与未验证内容)与 `CHANGELOG_ZH-CN.md`（本 HEAD 已知缺口）。

[![版本](https://img.shields.io/badge/version-4.2.0-purple)](https://github.com/fafa888uk/LilaShift-3.0/releases/tag/v4.2.0)
[![Build LilaShift IPA](https://github.com/fafa888uk/LilaShift-3.0/actions/workflows/build.yml/badge.svg)](https://github.com/fafa888uk/LilaShift-3.0/actions/workflows/build.yml)
[![Run Swift Tests](https://github.com/fafa888uk/LilaShift-3.0/actions/workflows/run-swift-tests.yml/badge.svg)](https://github.com/fafa888uk/LilaShift-3.0/actions/workflows/run-swift-tests.yml)
[![Check Licenses](https://github.com/fafa888uk/LilaShift-3.0/actions/workflows/check-licenses.yml/badge.svg)](https://github.com/fafa888uk/LilaShift-3.0/actions/workflows/check-licenses.yml)
[![SwiftLint](https://github.com/fafa888uk/LilaShift-3.0/actions/workflows/swiftlint.yml/badge.svg)](https://github.com/fafa888uk/LilaShift-3.0/actions/workflows/swiftlint.yml)
[![平台](https://img.shields.io/badge/iOS-27.x-black?logo=apple)](#兼容性)
[![协议](https://img.shields.io/badge/license-GPLv3-blue)](LICENSE)

> **关于仓库名称：** 本仓库已于 2026-11-17 从 `LilaShift-2.0` 改名为 `LilaShift-3.0`（账号也从 `fafa920q-hue` 改为 `fafa888uk`），旧链接会自动跳转到新地址，不会破坏已有的引用。

### 快速链接

- **下载：** [3.0.0-rc.1 发布页](https://github.com/fafa888uk/LilaShift-3.0/releases/tag/v3.0.0-rc.1) · [全部发布](https://github.com/fafa888uk/LilaShift-3.0/releases)
- **安装教程：** [docs/INSTALL_ZH-CN.md](docs/INSTALL_ZH-CN.md)
- **使用指南：** [docs/USER_GUIDE_ZH-CN.md](docs/USER_GUIDE_ZH-CN.md) · **兼容性：** [docs/COMPATIBILITY_ZH-CN.md](docs/COMPATIBILITY_ZH-CN.md) · **备份与恢复：** [docs/BACKUP_RESTORE_ZH-CN.md](docs/BACKUP_RESTORE_ZH-CN.md) · **故障排查：** [docs/TROUBLESHOOTING_ZH-CN.md](docs/TROUBLESHOOTING_ZH-CN.md) · **常见问题：** [docs/FAQ_ZH-CN.md](docs/FAQ_ZH-CN.md)
- **官方公告频道：** [Telegram 频道](https://t.me/LilaShiftUpdates)（仅发布公告：更新说明、测试通知、兼容性与已知问题。这是**频道，不是讨论群**，源码、下载和反馈都在 GitHub 上进行）
- **反馈 / 问题报告：** [GitHub Issues](https://github.com/fafa888uk/LilaShift-3.0/issues)（参见 [COMMUNITY.md](COMMUNITY.md)）。**请勿在 Issue 中发布序列号、UDID、账号密钥或其他个人数据。**

面向国行 iPhone 的一键 eSIM、区域代码与 Apple Intelligence 设置方案——基于上游 [GestaltX](https://github.com/huamidev/GestaltX) v1.0.7 的全量源码项目 LilaShift 3.0。

---

## 目录

- [已验证内容与未验证内容](#已验证内容与未验证内容)
- [本仓库是什么](#本仓库是什么)
- [3.0.0-rc.1 新增内容](#300-rc1-新增内容)
- [功能](#功能)
- [兼容性](#兼容性)
- [下载](#下载)
- [安装](#安装)
- [使用须知与注意事项](#使用须知与注意事项)
- [截图](#截图)
- [常见问题](#常见问题)
- [导入 plist](#导入-plist)
- [自行构建](#自行构建)
- [语言支持](#语言支持)
- [开源与协议](#开源与协议)
- [致谢](#致谢)
- [免责声明](#免责声明)

---

## 已验证内容与未验证内容

| 项目 | 当前预发布版状态 |
|---|---|
| CI 源码构建（`Build LilaShift IPA`） | ✅ 已通过 GitHub Actions 验证——见上方徽章 |
| Swift 单元测试（`Run Swift Tests`） | ✅ 已通过 GitHub Actions 验证——见上方徽章 |
| 许可证 / 署名检查（`Check Licenses`） | ✅ 已通过 GitHub Actions 验证 |
| 本版本 IPA 的真机安装 | ⚠️ **本版本未验证**——仓库中没有针对此 HEAD 的真机证据（见 `CHANGELOG_ZH-CN.md`，本 HEAD 已知缺口） |
| 解锁后的 eSIM 激活 | ⚠️ **本版本未验证**——仓库中没有针对此 HEAD 的真机证据 |
| Apple Intelligence 实际出现 / 可用 | ⚠️ **本版本未验证**——仓库中没有针对此 HEAD 的真机证据 |
| 恢复后设备是否回到原始状态 | ⚠️ **本版本未验证**——仓库中没有针对此 HEAD 的真机证据 |

修改 MobileGestalt 标志位**不等于**功能真正可用：标志位可能显示为"已开启"，但硬件、系统版本或 Apple 服务端仍可能拒绝。本文档不保证任何设备都能解锁全部功能。

## 本仓库是什么

本仓库是 LilaShift 3.0（紫序）的**完整源码项目**，是 GestaltX 的国行解锁增强版本。完整的修改源码都在本仓库中——没有单独的补丁步骤，CI 直接基于这份源码构建 IPA。

- 基于上游 [huamidev/GestaltX](https://github.com/huamidev/GestaltX) `v1.0.7`（提交 `dfd4a7e`，构建号 `11130112`），并合并了上游壁纸删除修复 PR #126（提交 `c60519c`）。
- 旧的基于补丁的构建仓库（[fafa888uk/LilaShift](https://github.com/fafa888uk/LilaShift)）保持原样，不再积极维护。
- 紫序增强功能维护者：**`@steam8871`**。上游 GestaltX 工作归功于 huamidev。

## 3.0.0-rc.1 新增内容

- **紫序 3.0 仪表盘**——轻量首页展示真实设备读取与待处理更改状态；58 项功能目录分为 11 个分类（45 项预设 + 13 项页面功能，统一排序规则：版本化 JSON + SHA-256 校验文件）；统一的 8 状态兼容性模型；带二次确认的历史/恢复视图；诊断缓存将文件读取与 SHA-256 计算移出渲染路径。详见 [CHANGELOG_ZH-CN.md](CHANGELOG_ZH-CN.md)。
- **一键国行解锁（10 项；原生 Apple Intelligence 机型 3 项）**——eSIM 开关（green-tea 关闭、not-green-tea 开启）、区域代码设为美国（`LL`，销售地区保持不变）、七项 Apple Intelligence 能力，全部一键暂存后再统一审核应用。
  - 应用前会先验证 eSIM 缓存布局；若无法验证，整个 eSIM 分组会停止并显示原因，区域与 AI 开关仍可单独设置。
  - 原生 Apple Intelligence 机型（如 iPhone Air）上 7 项 AI 会跳过——机器本身已有这些能力——一键只暂存 eSIM 两项 + 地区码。
  - 每次应用都会自动备份并回读校验。一键恢复可将全部已暂存项从记录的原始值还原。
- **独立 Siri AI 模式预设**——单独暂存 SiriMode = 2 的单项开关，与国行 AI、eSIM + 地区预设并列显示。与国行 AI 预设不同，它在原生 Apple Intelligence 机型上也可以使用（明确的单项选择）；但它是实验性的，在原生机型上通常不需要，因为 Siri AI 本来就能用。未知机型拒绝应用（fail-closed）。
- **浅紫色 Liquid Glass 全新设计**——页面背景 `#F6F3FF`，主色紫 `#8652DC`，无大面积深色背景。
- **每项功能下方的一句话用途说明**——所有预设都配有一行简体中文用途说明；设备要求与生效方式写在详情页中。
- **作者徽章与实时进度卡片**——维护者 `@steam8871` 在顶部和"关于"页中署名；读取与应用操作展示真实进度（备份 / 写入 / 校验 / 完成），均由实际操作驱动，绝不伪造。
- **开源合规**——"关于"页是一个开源贡献者中心，列出所有使用或参考过的项目及其作者、关系、关键技术、许可证和源码链接；完整 GPL v3.0 协议文本已内置于 App 中。详见 [docs/OPEN_SOURCE_REFERENCES.md](docs/OPEN_SOURCE_REFERENCES.md) 与 [docs/FEATURE_ORIGIN_MATRIX.md](docs/FEATURE_ORIGIN_MATRIX.md)。
- **MobileGestalt 写入过程加固**（设计思路参考 Erosion-CN，未复制任何代码）——原地写入（绝不预先截断、使用 `F_FULLFSYNC`、完整回读校验、失败时原地回滚）、运行时动态解析 eSIM 缓存布局、应用前差异预览、双保险库备份（含一个可在卸载/重装后存活的出厂保险库）、区域模式选择（仅区域代码，或完整美区 `LL` + `LL/A`）、带冲突检测的 4 因子 Apple Intelligence 体检。
- **因许可证原因移除 Respring**——NeoSpring/Ketamine 的 respring 实现已于 2026-11-14 移除（NeoSpring 未在任何地方声明许可证）。本版本中不含任何 respring 代码，改为显示手动重启设备的提示。详见 `docs/OPEN_SOURCE_REFERENCES.md` §3–§4。
- **紫序身份标识**——App 更名为**紫序 LilaShift**，以一张猫咪照片作为应用图标。

## 功能

| 分类 | 预设与工具 |
|---|---|
| 国行解锁 | 一键暂存 10 项（原生 Apple Intelligence 机型 3 项，7 项 AI 跳过）：eSIM 开关、区域代码美国（`LL`）、七项 Apple Intelligence 能力——应用前统一审核，包含 eSIM 缓存布局验证、自动备份、回读校验与一键恢复 |
| 显示 | 灵动岛能力与布局、常亮显示、AOD 鲜艳度、高亮度 AOD、AOD 翻页动画、HDR 照片显示、壁纸视差、Liquid Glass 低功耗渲染、实验性 PWM 与 DisplayPort 标志位 |
| 设备 | 型号名称、开关机提示音、充电限制、轻触唤醒、相机控制设置、操作按钮设置、碰撞检测 SOS、音频混合、空间 FaceTime 音频 |
| iPad | Apple Pencil 设置、台前调度能力、iPad 应用兼容性 |
| 智能 | 独立区域代码选项、Apple Intelligence 能力标志位、设备端 Siri、音频智能、个人翻译、照片清理、手写合成、常听 Hey Siri、Siri AI 模式（独立单项开关，原生 Apple Intelligence 机型也能用）、面向国行设备的销售地区选项（用于尝试激活） |
| 高级 | Apple 内部功能标志位、带显式确认的全局 InternalBuild 标志位、内部设置包、安全研究设备标志位 |
| 字段编辑器 | 读取、搜索、新增、编辑、删除 `CacheExtra` 字段；本地 plist 导入/导出；支持 String、Integer、Real、Boolean、Data、Date、Array、Dictionary 类型 |
| 更改记录 | 自动读取与手动重新读取、应用前后状态对比、写入校验、按预设单独恢复 |
| 备份 | 首次编辑设备前自动备份、每次写入前备份、保留原始值记录；支持打开、导出、恢复、删除 |
| 日志与重启 | 实际漏洞利用阶段日志、手动重启设备提示 |

通常只需修改区域代码即可尝试开启 Apple Intelligence，无需修改销售地区。将区域代码选为**美国**会把 `RegionCode` 设为 `LL`，并保留现有的销售地区后缀。也可以选择中国大陆、香港、台湾、日本或英国。销售地区与区域代码可以同时应用：销售后缀跟随销售地区设置，代码跟随区域代码设置。

> 如果你之前修改过销售地区，请先恢复设备原本的销售地区再应用。

关闭某个预设或使用其"还原"按钮，会恢复记录的原始值与类型；原本不存在的字段会被移除。如果某次较早的更改没有原始记录，只有在确定这些字段是被新增时，才使用"移除新增字段"。

预设修改的是能力标志位，实际效果取决于设备与系统版本。国行设备可通过 Apple Intelligence 与区域选项尝试激活，是否可用还取决于机型、系统版本与 Apple 服务端状态。

完整功能列表：[docs/FEATURES_ZH-CN.md](docs/FEATURES_ZH-CN.md)。

## 兼容性

支持 **iOS / iPadOS 27.x** 的设备端 MobileGestalt 访问。**iOS / iPadOS 26.x 不支持**设备端 MobileGestalt 访问（App 仍可安装——最低要求 iOS `26.0`——本地 plist 编辑功能仍可使用）。由 [worse_query](https://github.com/forcequitOS/worse_query) 驱动。SystemGroup 访问需要 iOS 27；具体可用功能取决于设备与系统版本。

签名需要具备至少一个可用 App Group 的证书和描述文件。请使用至少一个**共同的 App Group**（`group.com.huami.gestultx`）对 App 及其内嵌的分享扩展进行签名，重新签名时请保留该扩展。两个进程都会在运行时检测实际已签名的 App Group。分发的 IPA 带有 ad-hoc 签名并内嵌这些权限，使 SideStore 和 AltStore 在重签名时可以识别它们；**并非**使用开发者证书签名。

最简单的安装方式完全不需要签名：[LiveContainer](https://github.com/khanhduytran0/LiveContainer) 可以直接运行原始 IPA 而无需重新签名，因此无需付费开发者账号即可满足 App Group 要求。

完整兼容性表：[docs/COMPATIBILITY_ZH-CN.md](docs/COMPATIBILITY_ZH-CN.md)。

## 下载

从 [3.0.0-rc.1 发布页](https://github.com/fafa888uk/LilaShift-3.0/releases/tag/v3.0.0-rc.1) 下载 IPA——`LilaShift_3.0.0.ipa`（Bundle ID `com.huami.gestultx`，版本 `3.0.0`，构建号 `30000002`，最低要求 iOS `26.0`）。IPA 文件名由构建脚本（`.github/scripts/build-ipa.sh`）生成，格式为 `LilaShift_<版本号>.ipa`。

> 部分用户反馈在 iOS 27 的 Safari 中下载不完整。如果文件显示损坏或无法解压，请重新下载，可能需要多次尝试；若问题持续，请换一个浏览器试试。目前尚未确认具体原因。

## 安装

完整分步教程：[docs/INSTALL_ZH-CN.md](docs/INSTALL_ZH-CN.md)。简要版本：

1. 使用 [LiveContainer](https://github.com/khanhduytran0/LiveContainer) 安装 IPA（无需重签名），或使用 AltStore / SideStore / Sideloadly / 开发者证书重新签名——具体差异请参阅教程。
2. 打开紫序 LilaShift，先点击**读取设备**。
3. 打开**国行解锁**，查看待应用内容（多数机型 10 项；原生 Apple Intelligence 机型 3 项）后再应用。
4. 应用后**重启设备**——完全关机再开机，仅刷新 SpringBoard 对 eSIM 无效。然后在系统设置中检查 eSIM 和 Apple Intelligence。
5. 如需撤销全部更改，使用一键恢复——它会从备份中还原全部已暂存项。

> 请**不要**从第三方签名服务购买证书，也不要把 Apple ID 密码提供给任何人。如果某个方法要求你这样做，请立即停止。

## 使用须知与注意事项

- **需要 eSIM 硬件。** 本解锁只是翻转能力标志位，不会给没有 eSIM 硬件的设备添加硬件，软件无法凭空添加 eSIM 芯片。
- **Apple Intelligence 取决于硬件和 Apple 服务端。** 开启标志位不保证功能一定出现或可用。
- **运营商与地区限制对未解锁的手机依然有效。** 未解锁时，身处中国大陆无法安装境外 eSIM（Apple 规则）。解锁后，在中国大陆境内可以直接添加境外 eSIM，无需出境；在境外安装通常需要开启定位服务。国内运营商 eSIM 需在国内运营商营业厅激活。
- **系统更新可能会还原这些更改。** 更新 iOS 后如有需要请重新应用。
- **不要盲目更新 iOS。** GestaltX 依赖一个尚未修复的 iOS 沙盒逃逸漏洞（`worse_query`），Apple 未来版本可能会修复该漏洞。如果你依赖此工具，更新前请先确认兼容性。
- **应用前请先备份。** App 会自动备份，但单独做一次设备级别的备份仍是好习惯。
- **"恢复记录的原始值"不等于"真正的出厂状态"。** 恢复只能还原 App 自己记录下来的、修改前的值。如果某个值在 App 首次备份之前就已经被改过，那么备份里保存的就是那个已经改过的值。详见 [docs/BACKUP_RESTORE_ZH-CN.md](docs/BACKUP_RESTORE_ZH-CN.md)。

## 截图

本预发布版尚未包含截图。真机 3.0.0-rc.1 构建版本的真实截图将在可用后补充——这里没有伪造任何截图，早期模拟器截图（显示"尚未读取"状态，而非 10 项国行解锁汇总界面）也不会被当作本版本的截图展示。

## 常见问题

### 解锁后 eSIM 仍然无法使用，或"添加 eSIM"选项消失

- **双实体卡槽的 iPhone 18 Pro / Pro Max。** 这些机型的双实体卡槽与 eSIM 共用同一个基带通道。如果两个实体卡槽都插着卡，基带可能会隐藏"添加 eSIM"。解决方法：取出卡托（保持为空）→ 应用解锁 → 冷重启 → 添加 eSIM → 再插回实体卡。
- **仅刷新 SpringBoard 对 eSIM 无效。** 基带守护进程（`CommCenter`、`ctkd`）不会在 SpringBoard 刷新时重新加载缓存。应用后请完全关机再开机（冷重启）。
- **两个开关必须都打开。** 区域更改和 eSIM 更改必须同时应用；只改区域代码会让 eSIM 硬件锁依然生效。
- **切勿修改机型标识符（`ProductType`）。** 将国行机型（如 `iPhone19,7`）强制改为美版会破坏基带检测，导致 eSIM 菜单完全消失。
- **在中国大陆境内添加境外 eSIM，未解锁时会被 Apple 阻止。** 解锁后可直接在大陆境内添加，无需出境。（飞行模式 + 境外代理 Wi-Fi 只是未解锁时的变通办法。）
- **硬件限制。** 只有配备实体 eUICC 芯片的机型（iPhone Air、iPhone 18 系列等）才能添加 eSIM。更早期的仅双 Nano-SIM 机型没有 eUICC 芯片，该开关只能解锁 FaceTime 音频和 AI 区域访问。

### 预设页面和 MG Control 显示不一致

MG Control 显示的是 `CacheExtra` 的实时值，预设页面显示的是上一次读取的值。请先在首页点击**重新读取**。如果仍不一致，说明这些值是被直接写入的（绕过了预设）——应用一次一键解锁即可使其归一。

### AI 显示 1/7（或少于 7 项）

说明 7 项 AI 能力标志位中只有这些是开启状态。打开 Apple Intelligence 页面查看具体是哪些。旧版本做出的更改会一直保留在缓存中直到被还原；如果是在本 App 首次备份之前做出的更改，那么备份中已经包含了该更改。

### 想恢复原始状态，但没有备份

恢复功能只能还原 App 自己记录过的值。请先在"备份"页面检查是否有更早的备份记录。如果没有：

- 原本**不存在、后来被新增**的字段 → 使用"移除新增字段"，但仅限你确定是新增的字段。
- 原本**存在、被修改过**的字段 → 在 MG Control 中手动改回。`RegionCode` 和 AI 标志位属于 `CacheExtra` 键，可以在 MG Control 中搜索到。`green-tea` / `not-green-tea` 是 `CacheData` 槽位（#383 / #506），**无法搜索**——请改用 eSIM 预设来设置（`green-tea` → `true`，`not-green-tea` → `false`）。
- 恢复后请重启设备。

### AI 菜单没有出现，或 Siri 提示"出了点问题"

请检查区域代码是否为 `LL`、7 项 AI 标志位是否都已开启，以及设备是否已完成 AI 模型下载（需要 Wi-Fi + 充电，并静置一段时间）。代理规则也很关键：Siri 相关域名（`guzzoni.apple.com`、`*.siri.apple.com`、`dejavu.apple.com`、`sequoia.apple.com`）必须走**直连**，使用真实 IP，不能走代理；AI / Private Cloud Compute 相关域名需走干净的美国节点。如果你想保留国行的普通话来电防骚扰功能，请不要把系统地区设为美国——改设为台湾即可。

如果你用代理：Siri 核心域名必须直连真实 IP，不能走代理或 Fake-IP——`guzzoni.apple.com`、`*.siri.apple.com`、`dejavu.apple.com`、`sequoia.apple.com`、`*.smoot.apple.com`（Surge 里再把 `guzzoni.apple.com`、`*.guzzoni.apple.com`、`*.siri.apple.com` 加入 skip-proxy 与 always-real-ip）。AI 准入与私有云计算域名走干净的美区节点（须支持 UDP/QUIC）——`gspe1-ssl.ls.apple.com`、`*.issuer.apple.com`、`ropes.apple.com`、`mask-api.icloud.com`、`mask.icloud.com`、`mask-h2.icloud.com`、`*.app.apple.com`、`apple-relay.*`。不要对 `gspe1-ssl.ls.apple.com` 或 `*.smoot.apple.com` 开 MitM 解密。生成式功能报网络错误（如 Code=32033、Code=1009）时先查这几条。现成规则集：AppleFlow（github.com/Kianuni/AppleFlow）。来源：Erosion-CN FAQ Q3/Q6。

iOS 27.3 限制：国行硬件（CH/A）设备上，iOS 27.3 新增了直接读取硬件的资格检查（日志：`Eligibility returned no CN region policy on a CH region code device`）。即使地区码已是 LL、AI 开关全开，Siri AI 与部分生成式功能仍可能被拦截，改 MobileGestalt 绕不过去（Erosion-CN FAQ Q6 情况 C）。解决办法是留在或降回 iOS 27.2.x。

### 照片清理可用，但高质量清理 / 扩展 / 重新想象失败

在原生支持 AI 的 iPhone 上，出厂基线要求 `Personal Translator`（个人翻译）槽位 #266 = `true`，`Audio Intelligence`（音频智能）槽位 #178 = `false`。强制开启实验性的音频智能槽位可能破坏 ModelCatalog 资源检测，导致高质量清理失败。请关闭该项 / 恢复基线后再试。

### 重装 App，或证书过期

备份保存在 App 容器内部——卸载 App 会一并删除备份。在重装或证书过期前，请先导出备份。

更多问题：[docs/FAQ_ZH-CN.md](docs/FAQ_ZH-CN.md) 与 [docs/TROUBLESHOOTING_ZH-CN.md](docs/TROUBLESHOOTING_ZH-CN.md)。

## 导入 plist

在"文件"或其他 App 中选中一个 MobileGestalt plist 文件，点击**分享**，选择**紫序 LilaShift**。分享扩展会读取该文件并通过共享的 App Group 传递给主 App——如果没有自动跳转，请手动返回紫序 LilaShift。App 会校验来自 GestaltX 导出文件的设备绑定证明，或者从本设备获取至少两个唯一标识符，然后要求你确认导入。无法验证的文件会被拒绝。此前导入过的文件不会被用作设备身份的参考依据。

部分原始 plist 不包含任何唯一设备标识符——请先在本设备上用紫序 LilaShift 导出一份副本；其验证密钥保存在仅限本设备访问的 Keychain 中，不会包含在文件本身里。

共享文件会在启动时以及回到前台时进行检查。未保存的编辑会被保留，直到你保存或放弃为止。确认导入的文件会作为本地文档打开。**MG Control** 支持新增、编辑、重命名和删除带类型的键值。使用"恢复导入的 plist"可将已验证的文件恢复到本设备；恢复操作要求系统缓存布局匹配，并需要额外确认，会备份当前文件并校验写入结果。恢复后请重启设备。

## 自行构建

- **Build LilaShift IPA**（`.github/workflows/build.yml`）——在每次推送到 `main` 和 `feature/lilashift-3.0-dashboard`、每次 Pull Request、打版本标签、发布 Release，以及手动触发时，直接基于本仓库源码构建 IPA。IPA 会以 `LilaShift-<版本号>` 为名上传为工作流产物；打标签和发布 Release 时还会自动附加到对应的 GitHub Release。
- **Run Swift Tests**（`.github/workflows/run-swift-tests.yml`）——在 iOS 模拟器上运行 XCTest 测试套件。
- **Check Licenses**（`.github/workflows/check-licenses.yml`）——在每次可构建 IPA 的推送上运行 `scripts/check-licenses.py`。
- **Prepare Draft Release**（`.github/workflows/prepare-release.yml`，仅支持手动触发）——构建 IPA 并创建一个**草稿** GitHub Release，绝不会自动发布。

## 语言支持

GestaltX 跟随你的 iOS 语言设置，默认语言与回退语言为英语。波斯语支持从右到左的布局。

| 语言 | Locale |
|---|---|
| English | `en` |
| 简体中文 | `zh-Hans` |
| 繁體中文（台灣） | `zh-Hant-TW` |
| 繁體中文（香港） | `zh-Hant-HK` |
| Tiếng Việt — 越南语 | `vi` |
| Русский — 俄语 | `ru` |
| فارسی — 波斯语 | `fa` |
| 한국어 — 韩语 | `ko` |
| Español — 西班牙语 | `es` |
| 日本語 — 日语 | `ja` |

## 开源与协议

本项目以 **GNU General Public License v3.0** 协议发布——详见 [LICENSE](LICENSE)（与上游 v1.0.7 的协议文本完全一致）。

- 上游项目：[huamidev/GestaltX](https://github.com/huamidev/GestaltX)（`v1.0.7`，提交 `dfd4a7e`，加上 PR #126，提交 `c60519c`）
- 增强版维护者：`@steam8871`
- 本版本中的修改内容：国行解锁预设（10 项；原生 Apple Intelligence 机型 3 项）及其安全检查、浅紫色 Liquid Glass 重新设计、每项功能的一句话用途说明、作者徽章与进度卡片、App 内源码仓库链接、开源合规页面、参考 Erosion-CN 思路做的加固（写入路径、动态布局解析、差异预览、双保险库备份、区域模式、AI 体检）、紫序品牌重塑，以及猫咪应用图标。
- LilaShift 3.0 新增内容：轻量仪表盘、58 项功能目录、统一兼容性模型、历史/恢复视图、诊断缓存，以及带每个项目来源记录的开源贡献者中心（"关于"页），详细记录见 `docs/OPEN_SOURCE_REFERENCES.md`。
- 完整的对应源码均在本仓库中（全量源码，无单独补丁步骤）。

## 致谢

- **huamidev** —— GestaltX
- [forcequitOS / Taj C — worse_query](https://github.com/forcequitOS/worse_query)
- [neonmodder123](https://github.com/neonmodder123)
- [skadz108](https://github.com/skadz108)
- [rooootdev — NeoSpring](https://github.com/rooootdev/neospring)（未声明许可证；respring 功能已于 2026-11-14 暂停使用并移除——详见 `docs/OPEN_SOURCE_REFERENCES.md`）
- [Nouvborne — Ketamine](https://github.com/Nouvborne/Ketamine)
- [huamidev — LCSign](https://sign.lc)
- [Kianuni — Erosion-CN](https://github.com/Kianuni/Erosion-CN)
- [lunginspector / jailbreak.party — Erosion](https://github.com/jailbreakdotparty/Erosion)
- [sasobhabha — Gester](https://github.com/sasobhabha/Gester)
- [Thomas Zoechling — ZIPFoundation](https://github.com/weichsel/ZIPFoundation)
- [GitHub Inc. — Primer Octicons](https://github.com/primer/octicons)
- [PoomSmart — MGKeys](https://github.com/PoomSmart/MGKeys)
- [leminlimez — Nugget](https://github.com/leminlimez/Nugget)（AGPL-3.0，仅作参考，未移植代码）
- [rooootdev — mond](https://github.com/rooootdev/mond)（AGPL-3.0，仅作参考，未移植代码）
- [frs0n — GestaltEdit](https://github.com/frs0n/GestaltEdit)
- [Point-Free — SnapshotTesting](https://github.com/pointfreeco/swift-snapshot-testing)（测试工具，未打包进 App）
- [Realm — SwiftLint](https://github.com/realm/SwiftLint)（构建工具，未打包进 App）

完整的逐项目记录（许可证、证据、关系、涉及文件、是否打包进 IPA）：[docs/OPEN_SOURCE_REFERENCES.md](docs/OPEN_SOURCE_REFERENCES.md)。逐功能来源对照表：[docs/FEATURE_ORIGIN_MATRIX.md](docs/FEATURE_ORIGIN_MATRIX.md)。

## 免责声明

本项目为非官方修改版本，与 Apple 无关，也未获得上游作者背书。仅用于安全研究与学习目的。请仅在你拥有或已获得授权管理的设备上使用。

修改前请备份你的数据。修改 MobileGestalt 可能导致系统不稳定，或需要恢复设备。能力标志位不保证功能一定可用。你需要对自己应用的更改及由此产生的风险负责。

## License

[GNU GPL v3](LICENSE) · Copyright © 2026 huamidev。国行解锁增强功能由 `@steam8871` 维护。
