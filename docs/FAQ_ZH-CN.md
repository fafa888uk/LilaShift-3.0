# LilaShift 3.0 常见问题（FAQ）

> 版本：LilaShift 3.0.0-rc.1（**预发布，非稳定版**）
> 维护者：@steam8871
>
> 本页回答最常被问到的问题。更详细的步骤见安装教程、使用指南与故障排查；
> 回答里凡写“待验证”，表示尚未用本版在真机上确认。

## 目录

- [这是什么？能干什么？](#这是什么能干什么)
- [安装与版本](#安装与版本)
- [eSIM](#esim)
- [Apple Intelligence](#apple-intelligence)
- [备份与还原](#备份与还原)
- [证书与重签](#证书与重签)
- [安全与隐私](#安全与隐私)
- [反馈与更新](#反馈与更新)

---

## 这是什么？能干什么？

### LilaShift 是什么？

LilaShift（紫序）是 GestaltX 的国行增强版：一个 iOS 应用，用来查看与修改
本机 MobileGestalt 能力标记（如 eSIM 开关、地区码、Apple Intelligence
能力等），带备份与还原。完整源码在
[fafa888uk/LilaShift-3.0](https://github.com/fafa888uk/LilaShift-3.0)，
基于上游 huamidev/GestaltX v1.0.7，遵循 GPL v3.0。

### 3.0.0-rc.1 是稳定版吗？

**不是。** `rc.1` 是预发布（Pre-release）：功能已就绪、CI 构建与测试已跑通，
但**没有真机验证**。请先读 README 顶部的验证情况表，再决定要不要装。
稳定版发布前会去掉 `rc` 标记并另行公告。

### 改一个开关，功能就一定能用吗？

**不一定。** LilaShift 改的是能力标记（capability flag），功能最终能不能跑，
还要看硬件、系统版本与苹果服务。开关显示“已开”不等于功能已生效。
App 里每个功能都有 8 状态兼容性标识，会标出“不支持 / 未验证”的项。

### 哪些设备能解锁全部功能？

没有“全部设备都能解锁全部功能”的承诺。eSIM 需要 eUICC 硬件；Apple
Intelligence 需要硬件 + 系统 + 服务同时满足；灵动岛、AOD 等取决于机型。
详见 [COMPATIBILITY_ZH-CN.md](COMPATIBILITY_ZH-CN.md)。

## 安装与版本

### 在哪里下载？

只从本仓库 Releases 页下载：
[LilaShift 3.0.0-rc.1 发布页](https://github.com/fafa888uk/LilaShift-3.0/releases/tag/v3.0.0-rc.1)，
文件 `LilaShift_3.0.0.ipa`。不要从不明渠道下载。

### 没有电脑能装吗？

可以，用 LiveContainer 方式（装容器本身可能需要一次侧载）。详见
[INSTALL_ZH-CN.md](INSTALL_ZH-CN.md) 方式 A。**本版 IPA 用该方式在真机上
走通待验证。**

### 需要越狱吗？

不需要。LilaShift 通过 `worse_query` 沙盒逃逸读写 MobileGestalt，
不需要越狱。但它依赖的漏洞可能在未来系统更新中被苹果修掉，升级前请先
确认兼容性。

### 支持 iOS 26 吗？

可以安装（最低 iOS 26.0），但 26.x 上**不支持本机 MobileGestalt 访问**，
只能用本地 plist 编辑。本机访问需要 iOS / iPadOS 27.x。

### 截图在哪里？

本预发布暂不附截图。真实截图将在真机上跑通 3.0.0-rc.1 后补上；
此处不放拼造图，也不把旧版模拟器截图当成本版截图。

## eSIM

### 解锁后就能加 eSIM 吗？

不一定。解锁只改能力开关，能不能加 eSIM最终看硬件（须有 eUICC 芯片）
与运营商 / 苹果规则。没有 eUICC 芯片的机型加不了 eSIM。

### 在中国大陆能加境外 eSIM 吗？

未解锁时不能（苹果规则），会被拦截。解锁后可以：在中国大陆境内直接
扫码添加境外 eSIM，无需出境。飞行模式 + 连 Wi-Fi（挂海外代理）是未解
锁时的变通办法。

### 解锁后「添加 eSIM」消失了怎么办？

见 [TROUBLESHOOTING_ZH-CN.md](TROUBLESHOOTING_ZH-CN.md) 第 4 节：
先冷重启；确认 9 项都应用了；双实体卡机型先拔卡托；绝不要改 `ProductType`。

### 改机型标识能“变成美版”吗？

**不要改。** 把国行主板（如 `iPhone19,7`）强改成美版会让基带校验失配，
eSIM 菜单整个消失。

## Apple Intelligence

### 打开开关后 AI 菜单还是不出现？

按顺序查：地区码 `LL`、6 项全开、模型是否下完（Wi-Fi + 充电静置）、
Siri 域名是否直连、机型本身是否支持。详见故障排查第 5 节。

### AI 显示 1/6 是什么意思？

6 项 AI 能力里只有 1 项是开着的。点进 Apple 智能页看是哪几项。

### 照片高质量消除报错，但快速消除正常？

原生 AI 机型出厂基线要求 `Personal Translator` 槽位 #266 = `true`、
`Audio Intelligence` 槽位 #178 = `false`。强开实验性 Audio Intelligence
可能导致报错，关掉、恢复基线再试（待用本版在真机上复核）。

## 备份与还原

### 还原能回到出厂状态吗？

**不能保证。** 还原只会写回 App 自己记录的原值。如果某值在 App 第一次
备份前就被改过，备份里存的就是改过之后的值。详见
[BACKUP_RESTORE_ZH-CN.md](BACKUP_RESTORE_ZH-CN.md)。

### 卸载 App 后备份还在吗？

容器内的普通备份会被删掉（出厂金库除外）。重装、证书过期、换机前务必先
导出备份。

### 没有备份怎么还原？

新增的键用「移除新增字段」（只删确定是后来加的）；改了值的键在 MG 控制里
手动改回去（eSIM 两项走 eSIM 预设）。详见备份文档第 6 节。

## 证书与重签

### 免费 Apple ID 签名能用多久？

按 Apple 免费个人账号的公开规则，证书有效期 7 天，到期前需刷新续签；
同时有效的自签应用数量有限。**待用本版 IPA 核实。**

### 证书过期后应用打不开怎么办？

重新签名 / 刷新即可（按安装教程里对应方式）。数据一般还在，但为防万一，
刷新前请先导出备份。

### 重签时能去掉分享扩展吗？

**不能。** 主应用与分享扩展必须签入同一个 App Group，扩展必须保留，
否则分享导入与备份共享会异常。

### 需要买证书吗？

**不需要，也不建议。** 不要向第三方签名服务购买证书，不要使用来路不明的
“企业证书”。免费个人账号或 LiveContainer 已够用。

## 安全与隐私

### LilaShift 会上传我的数据吗？

不会。读取、备份、写入都在本机完成；App 不上传设备数据。报 Bug 时请
**不要**贴序列号、UDID、IMEI、Apple ID、账号密钥或含个人标识的完整日志。

### 安装时要交 Apple ID 密码吗？

**不要交给任何人。** 只在苹果官方登录界面或你自己电脑上的正规工具
（AltStore / SideStore / Sideloadly / Xcode）里输入。任何人索要你的
Apple ID 密码都是骗局。

### 改 MobileGestalt 有风险吗？

有。可能导致系统不稳定，严重时需要恢复设备。改动前请备份（整机备份 +
App 自动备份），只改你明白的项，只在自己持有或已获授权的设备上使用。

## 反馈与更新

### 在哪里反馈问题？

GitHub Issues：
[https://github.com/fafa888uk/LilaShift-3.0/issues](https://github.com/fafa888uk/LilaShift-3.0/issues)。
不要在 Telegram 频道反馈——频道只发公告，不受理反馈。

### 在哪里看更新通知？

Telegram 更新频道
[LilaShift 紫序 · 更新公告](https://t.me/LilaShiftUpdates)（频道，只发公告，
不是讨论群）与本仓库 Releases 页。

### 我能参与贡献吗？

可以。见 [CONTRIBUTING.md](../CONTRIBUTING.md)：先读开源合规要求
（署名与许可证义务），不要提交无许可证来源的代码。

---

相关文档：[安装教程](INSTALL_ZH-CN.md) · [使用指南](USER_GUIDE_ZH-CN.md) ·
[兼容性](COMPATIBILITY_ZH-CN.md) · [备份与还原](BACKUP_RESTORE_ZH-CN.md) ·
[故障排查](TROUBLESHOOTING_ZH-CN.md) · [功能清单](FEATURES_ZH-CN.md)
