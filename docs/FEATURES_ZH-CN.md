# LilaShift 3.0 功能清单

> 版本：LilaShift 3.0.0-rc.1（**预发布，非稳定版**）
> 维护者：@steam8871 · 上游：huamidev/GestaltX v1.0.7
>
> **说明：** 本清单按源码中的功能目录（`GestaltX/FeatureCatalog.swift`：
> 46 个预设项 + 13 个页面项 = 59 项，11 个分类）与既有 README 整理。
> 每个功能名下都有一句简体中文用途说明（App 内查看）。
> **“有这个开关”≠“改了就能用”**：实际效果取决于设备、系统版本与苹果服务，
> 8 状态兼容性标识会标出每项的真实状态（见使用指南第 3 节）。
> 逐功能来源映射见 [FEATURE_ORIGIN_MATRIX.md](FEATURE_ORIGIN_MATRIX.md)。

## 1. 智能解锁（smartUnlock）

| 功能 | 说明 |
| --- | --- |
| 一键解锁（10 项） | eSIM 两项开关 + 地区码 `LL` + 7 项 AI 能力，一次暂存、确认后应用；带 eSIM 缓存布局校验、自动备份、写回校验、一键还原 |

## 2. Apple 智能（appleIntelligence）

| 功能 | 说明 |
| --- | --- |
| Apple 智能能力标记 | Apple Intelligence 总开关（能力标记） |
| 端侧 Siri | 设备端 Siri 能力值（保留设备原有值，不会被通用值覆盖） |
| 音频智能 | iOS 27 音频智能能力；原生 AI 机型出厂基线要求该槽位 #178 = `false`，强开可能导致照片高质量消除报错 |
| 个人翻译 | 个人翻译能力；原生 AI 机型出厂基线要求槽位 #266 = `true` |
| 照片消除 | Photos Clean Up（照片消除）能力 |
| 手写合成 | 手写合成能力 |
| 常听 Hey Siri | 始终聆听 Hey Siri |
| Siri AI 模式（独立预设） | 单独把 Siri 切到 AI 模式（SiriMode = 2）；与国行 AI 预设不同，原生 Apple Intelligence 机型也能用（明确的单项选择），但属实验性，原生机型通常不需要；未知机型拒绝应用 |
| 地区代码选项 | 独立的地区代码选项（美国 `LL` / 中国大陆 / 香港 / 台湾 / 日本 / 英国） |
| 销售地区选项 | 销售地区选项；通常只改地区码就够了，不用改销售地区 |

## 3. eSIM 与地区（esimRegion）

| 功能 | 说明 |
| --- | --- |
| eSIM 开关 green-tea / not-green-tea | CacheData 槽位 #383 / #506；暂存前校验 eSIM 缓存布局，验不过整组停住 |
| 地区码 | `RegionCode` 设置 |
| 地区模式二选一 | 只改地区码，或完整美国 `LL` + `LL/A` |

## 4. 屏幕与锁定（screenLock）

| 功能 | 说明 |
| --- | --- |
| 灵动岛功能标记与布局 | Dynamic Island 能力与布局；还原时布局与能力标记一起恢复 |
| 全天候显示（AOD） | Always-On Display 开关 |
| AOD 色彩 | AOD Vibrancy |
| 高亮度 AOD | 高亮度全天候显示 |
| AOD 翻页组件 | AOD flipbook 及其条目数量 |
| HDR 照片显示 | HDR 照片显示能力 |
| 壁纸视差 | 壁纸视差控制 |
| 液态玻璃低性能渲染 | Liquid Glass 低性能渲染 |
| 实验性 PWM / DisplayPort 标记 | 实验性能力标记，按设备而定 |

## 5. 系统设置（systemSettings）

| 功能 | 说明 |
| --- | --- |
| 锁屏文字 | 自定义锁屏底部文字，即时生效，无需重启 |
| WAPI | 关闭 WAPI 监管标志或恢复原值；缓存布尔值从本机 MobileGestalt 镜像解析，非硬编码槽位 |
| 内部设置包 | Apple 内部设置 bundle |
| InternalBuild | 系统全局 InternalBuild 标记，开启前有单独确认 |

## 6. 个性化（personalization）

| 功能 | 说明 |
| --- | --- |
| 壁纸设置 | 导入、添加、移除壁纸包；支持 `.tendies` 与 `.zip` 导入（可经分享扩展） |
| App 启动图 | 自选照片、将当前启动图以原尺寸保存到相册、自动备份和还原 |
| 机型名称 | 设备型号名称显示 |
| 开关机提示音 | Boot / shutdown chime |
| 充电上限 | Charge limit |
| 轻点唤醒 | Tap to wake |

## 7. 启动图（launchArtwork）

| 功能 | 说明 |
| --- | --- |
| App 启动图管理 | 与第 6 节的启动图同一功能在目录中的入口：导入、保存、备份、还原 |

## 8. 设备诊断（deviceDiagnostics）

| 功能 | 说明 |
| --- | --- |
| 设备概况 | 机型、系统版本、读取状态 |
| 智能故障诊断 | 诊断卡片（电池、连接、缓存等），11 张诊断卡在二级页面查看 |
| 系统健康评分 | 系统健康评分卡片 |
| Apple 智能体检（4 要素） | 四要素 AI checkup 与槽位级冲突防呆 |
| 日志 | 实际漏洞利用过程日志，可分享导出 |

## 9. 已改记录（modifiedRecords）

| 功能 | 说明 |
| --- | --- |
| 更改管理 | 自动读取、手动重新读取、暂存更改前后对比（Diff 预览）、写入验证、逐项还原 |
| 历史恢复视图 | 带二次确认的历史记录与恢复入口 |

## 10. 备份与还原（backupRestore）

| 功能 | 说明 |
| --- | --- |
| 自动备份 | 首次读取自动备份、每次写入前备份、原值记录 |
| 备份管理 | 打开、导出、恢复、删除备份 |
| 双金库备份 | 普通备份 + 卸载重装后仍在的出厂金库 |
| 恢复导入的 plist | 将已核验的 plist 文件恢复到本机（核对缓存布局、二次确认、先备份再写入并验证） |

## 11. 高级工具（advancedTools）

| 功能 | 说明 |
| --- | --- |
| MG 控制（字段编辑） | 读取、搜索、添加、编辑、删除 `CacheExtra` 字段；String / Integer / Real / Boolean / Data / Date / Array / Dictionary |
| 本地 plist 编辑 | 本地 plist 文档的打开、编辑、导入、导出 |
| Apple 内部功能标记 | Apple 内部 feature flags |
| 安全研究设备标记 | Security Research Device flag |
| 相机控制设置 | Camera Control 设置 |
| 操作按钮设置 | Action Button 设置 |
| 车祸检测 SOS | Collision SOS |
| 音频混音 | Audio Mix |
| FaceTime 空间音频 | Spatial FaceTime audio |
| Apple Pencil 设置 | 仅 iPad |
| 台前调度 | Stage Manager 能力标记，仅 iPad |
| iPad 应用兼容性 | 仅 iPad |

## 不在 3.0.0-rc.1 里的功能

| 功能 | 状态 |
| --- | --- |
| 自动注销（respring） | **已移除**（2026-11-14）：NeoSpring 未声明许可证，相关实现已删除；改为手动重启设备提示 |

---

相关文档：[使用指南](USER_GUIDE_ZH-CN.md) · [兼容性](COMPATIBILITY_ZH-CN.md) ·
[备份与还原](BACKUP_RESTORE_ZH-CN.md) · [故障排查](TROUBLESHOOTING_ZH-CN.md) ·
[常见问题](FAQ_ZH-CN.md)
