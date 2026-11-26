# LilaShift 3.0 兼容性说明

> 版本：LilaShift 3.0.0-rc.1（**预发布，非稳定版**）
> 维护者：@steam8871 · 上游：huamidev/GestaltX v1.0.7
>
> **验证状态：** 本页的系统与机型要求来自本仓库源码与既有文档（README、
> CHANGELOG、源码注释）。**本版未在真机上逐机型验证**：下表是“按设计应支持”
> 的范围，不是“已在每台机型上测过”的清单。凡标“待验证”，表示尚未用本版
> 在真机上确认。

## 1. 系统版本

| 系统 | 本机 MobileGestalt 访问 | 本地 plist 编辑 | 说明 |
| --- | --- | --- | --- |
| iOS / iPadOS 27.x | 支持 | 支持 | 完整功能；SystemGroup 访问需要 iOS 27 |
| iOS / iPadOS 26.x | **不支持** | 支持 | 可安装（最低 iOS 26.0），但本机访问提示不支持 |
| iOS / iPadOS 25.x 及更早 | 不支持 | 待验证 | 不在支持范围 |

- 最低安装版本（`IPHONEOS_DEPLOYMENT_TARGET`）：iOS 26.0。
- LilaShift 依赖一个未修复的 iOS 沙盒逃逸漏洞（`worse_query`，
  forcequitOS）。苹果可能在未来系统更新中修掉它；**升级 iOS 前请先确认
  兼容性**（Telegram 更新频道与 Releases 公告），不要盲目升级。
- 系统更新可能还原已做的改动；升级后如需继续使用，按使用指南重新应用。

## 2. 机型与硬件

### 2.1 eSIM：一句话先说清

**软件不能给没有 eSIM 芯片的设备变出一块 eSIM 芯片。** 一键解锁只改能力
开关（`green-tea` / `not-green-tea`），能不能加 eSIM，最终看硬件。

| 机型情况 | 能否加 eSIM | 备注 |
| --- | --- | --- |
| 带物理 eUICC 芯片的机型（iPhone Air、iPhone 18 系列等） | 可以尝试 | 解锁后仍需按运营商与苹果规则开通 |
| 早期纯双实体卡槽、主板空焊 eUICC 的机型 | **不能** | 开关只能解锁 FaceTime 音频与 AI 地区准入 |
| iPhone 18 Pro / Pro Max（双实体卡 + eSIM 三通道复用） | 可以，但有条件 | 两个实体卡槽都占着时基带可能隐藏「添加 eSIM」；解决：先拔出卡托（空卡状态），应用解锁后冷重启，加上 eSIM，再插回实体卡 |

### 2.2 Apple Intelligence

Apple Intelligence 能不能出现、能不能用，取决于**四件事同时成立**：

1. 机型硬件支持（苹果对 AI 机型的要求）；
2. 系统版本支持；
3. 地区码 / 销售地区设置正确（`RegionCode` 为 `LL` 等）；
4. 苹果服务可用（模型下载、服务器连通）。

只改开关（第 3 项）解决不了第 1、2、4 项。**打开开关 ≠ 功能一定出现。**
本版在真机上的 AI 开通**未验证**。

已知细节（来自既有文档与用户反馈，**待用本版在真机上复核**）：

- 原生 AI 机型的出厂基线要求 `Personal Translator` 槽位 #266 = `true`、
  `Audio Intelligence` 槽位 #178 = `false`。强开实验性的 Audio Intelligence
  槽位可能让 ModelCatalog 资产校验断路，导致照片高质量消除 / 扩图延伸 /
  重构报错。关掉它、恢复基线再试。
- AI 显示 1/7（或不到 7）：说明 7 项 AI 能力里只有这么多项是开着的，
  点进 Apple 智能页看是哪几项。
- 模型下载需要 Wi-Fi + 充电、静置一段时间；Siri 相关域名须直连
  （见 [TROUBLESHOOTING_ZH-CN.md](TROUBLESHOOTING_ZH-CN.md)）。

### 2.3 其他功能：按设备而定

- 灵动岛、AOD（全天候显示）、相机控制、操作按钮、Apple Pencil、台前调度：
  均取决于机型本身有没有对应硬件 / 苹果有没有在该机型上开放。
  预设页的 8 状态兼容性标识会标出“不支持”的项——**不要强行改不支持的项**。
- iPad 相关预设只在 iPad 上有意义；iPhone 上看到“不支持”是正常的。

## 3. 安装方式兼容性

| 方式 | 要求 | 备注 |
| --- | --- | --- |
| LiveContainer | iOS 27.x 设备（本机访问） | 不用重签；装容器本身可能需要一次侧载 |
| AltStore / SideStore / Sideloadly | 个人 Apple ID | 免费账号证书 7 天有效，需定期刷新；重签须保留分享扩展与共同 App Group |
| 付费开发者证书 / Xcode | Apple Developer Program 账号 | 描述文件须含 App Group |

各方式的详细步骤与验证状态见 [INSTALL_ZH-CN.md](INSTALL_ZH-CN.md)。
**所有安装方式用本版 IPA 在真机上走通均待验证。**

## 4. 语言

App 跟随 iOS 语言设置，默认及回退语言为英语；波斯语支持从右向左布局。
支持：英语、简体中文、繁體中文（台灣）、繁體中文（香港）、越南语、俄语、
波斯语、韩语、西班牙语、日语。

## 5. 不支持的场景

- **不要改机型标识（`ProductType`）。** 把国行主板（如 `iPhone19,7`）强改
  成美版会让基带校验失配，eSIM 菜单整个消失。
- **不要在没有备份的情况下改动。** 还原只能恢复 App 记录过的原值。
- **不要升级到未经确认的系统版本。** 见第 1 节。
- **未解锁的手机在中国大陆境内无法安装境外 eSIM**（苹果规则）；解锁后可
  在大陆境内直接添加境外 eSIM，无需出境。在境外安装通常需要打开定位服
  务；中国运营商 eSIM 须在中国营业厅激活。

## 6. 待验证清单（本版）

- [ ] 各机型（iPhone Air、iPhone 18 系列、国行双卡机型等）上 3.0.0-rc.1
      的安装与读取
- [ ] eSIM 解锁后在真机上实际开通 eSIM
- [ ] Apple Intelligence 在真机上实际出现与可用
- [ ] 各安装方式（LiveContainer / AltStore / SideStore / Sideloadly /
      开发者证书）用本版 IPA 在真机上走通
- [ ] 免费 Apple ID 的 7 天续签流程用本版 IPA 核实
- [ ] 还原后设备状态与改动前一致（真机）

验证结果出来后，本页与 CHANGELOG 会更新；公告发在 Telegram 更新频道
[LilaShift 紫序 · 更新公告](https://t.me/LilaShiftUpdates)。

---

相关文档：[安装教程](INSTALL_ZH-CN.md) · [使用指南](USER_GUIDE_ZH-CN.md) ·
[备份与还原](BACKUP_RESTORE_ZH-CN.md) · [故障排查](TROUBLESHOOTING_ZH-CN.md) ·
[常见问题](FAQ_ZH-CN.md)
