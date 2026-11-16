# LilaShift 3.0 — 开源来源清单（Open Source References）

> 核实日期：2026-11-14。许可证以各仓库 `LICENSE` 文件与 GitHub 标注为准；
> 源码使用关系以本仓库实际源码、Git 历史与 `THIRD_PARTY_NOTICES.md` 为准。
> 本文件与 `THIRD_PARTY_NOTICES.md`（随 App 分发）同步维护；两者不一致时以
> `THIRD_PARTY_NOTICES.md` 为准并在此记录差异原因。
>
> 使用关系定义：
> - **原始代码基础**：整个 App 构建于其上。
> - **直接集成**：第三方代码原样（或接近原样）包含在 App 内。
> - **改编**：第三方代码/设计被改写后使用，保留原作者归属。
> - **复用数据**：仅数值/映射表被转录，代码重新实现。
> - **设计参考**：只参考设计思路，未复制代码。
> - **研究参考**：只对照键名与工作流程，未复制代码或数据。
> - **尚未核实**：关系或许可证无法从公开来源确认。

---

## 1. GestaltX — 原始代码基础

| 项目 | 内容 |
|---|---|
| 作者 / 组织 | huamidev |
| GitHub | https://github.com/huamidev/GestaltX |
| 使用的版本 / 提交 | 上游 v1.0.7（tag `dfd4a7e`，build `11130112`），main `c60519c`（含上游壁纸删除修复 PR #126） |
| 许可证 | **GPL-3.0**（仓库 `LICENSE` + GitHub 标注一致；`GNU GENERAL PUBLIC LICENSE / Version 3, 29 June 2007`） |
| 证据来源 | https://github.com/huamidev/GestaltX/blob/main/LICENSE |
| LilaShift 对应功能 | 整个 App：MobileGestalt 编辑器、预设、备份、事务、暂存模型、界面 |
| 对应源码文件 | 全部上游来源文件（见 `THIRD_PARTY_NOTICES.md` §1）；LilaShift 在此基线上新增的文件见 `docs/FEATURE_ORIGIN_MATRIX.md` |
| 使用关系 | **原始代码基础** |
| 主要修改 | 国行一键解锁、浅紫 Liquid Glass 界面、AI 体检、安全写入加固、双金库备份、预设目录、个性化中心、3.0 首页/目录/兼容性模型（均在 `FEATURE_ORIGIN_MATRIX.md` 中逐项列出） |
| 是否打包进入 IPA | 是（整个 App 即基于此基线构建） |
| 版权与许可证义务 | 保留 huamidev 署名与 GPL v3 全文（`GestaltX/Licenses/GestaltX-GPL-3.0.txt`，与仓库根 `LICENSE` 逐字节相同）；衍生作品同样以 GPL-3.0 发布；App 内「关于」页与 `THIRD_PARTY_NOTICES.md` 均保留原始作者信息 |
| 仍需人工确认 | 否 |

## 2. worse_query — 直接集成

| 项目 | 内容 |
|---|---|
| 作者 / 组织 | Taj C（forcequit / forcequitOS） |
| GitHub | https://github.com/forcequitOS/worse_query |
| 使用的版本 / 提交 | 2026-11-09 原样引入；上游 main 最后推送 2026-11-08。引入时的上游确切提交**尚未核实**（低优先级：文件自带完整 GPL 声明与作者信息） |
| 许可证 | **GPL-3.0-or-later**（仓库 `LICENSE` 为 GPL v3 文本；源码头明确写明 "either version 3 of the License, or (at your option) any later version"，以源码头为准） |
| 证据来源 | https://github.com/forcequitOS/worse_query/blob/main/LICENSE；本地 `GestaltX/worse_query.h`、`.m` 头部 |
| LilaShift 对应功能 | 沙盒逃逸（MobileGestalt 缓存读写的前提）、容器身份发现（forcequitOS 的 fsgetpath 研究，`GXCustomizationAccess.m`） |
| 对应源码文件 | `GestaltX/worse_query.m`、`GestaltX/worse_query.h`（原样引入，头部已补 SPDX `GPL-3.0-or-later` 与来源 URL） |
| 使用关系 | **直接集成**（原样引入） |
| 主要修改 | 无修改；仅在文件头补充 SPDX 与来源 URL（不改动上游声明本身） |
| 是否打包进入 IPA | 是 |
| 版权与许可证义务 | 保留 Taj C（forcequit）版权声明与 GPL 声明；衍生作品同样 GPL（LilaShift 已是 GPL-3.0，兼容；注意本文件是 `-or-later`，不是仓库其余文件的 `GPL-3.0-only`） |
| 仍需人工确认 | 建议确认引入时的上游确切提交（低优先级） |

## 3. Ketamine — 改编

| 项目 | 内容 |
|---|---|
| 作者 / 组织 | Nouvborne |
| GitHub | https://github.com/Nouvborne/Ketamine |
| 使用的版本 / 提交 | 默认分支 `master`，最后推送 2026-09-21。改编依据的确切提交**尚未核实**（低优先级） |
| 许可证 | **GPL-3.0**（仓库 `LICENSE`；README："Ketamine is licensed under the **GNU General Public License v3.0**"） |
| 证据来源 | https://github.com/Nouvborne/Ketamine/blob/master/LICENSE |
| LilaShift 对应功能 | Respring（已暂停移除，2026-11-14；见下） |
| 对应源码文件 | `GestaltX/NeoSpringView.swift`（已删除，2026-11-14；原为上游 GestaltX 的改编实现） |
| 使用关系 | **已暂停（改编已移除，2026-11-14）**：原为**改编**（经上游 GestaltX 改编；原始 WebKit 技术来自 neonmodder123，Swift 实现来自 skadz108）。因同一技术链路的 NeoSpring 无许可证声明，改编实现为单一混合文件、无法分割出可干净授权的部分，故整段实现已全部移除 |
| 主要修改 | 上游 GestaltX 2026-11-09 的修改：修正 raw-string 关闭标签转义与 Web Crypto 请求长度；增加超时、取消、非持久 WebKit 数据存储与模拟器排除（已随文件删除而移除） |
| 是否打包进入 IPA | **否（2026-11-14 起不再打包）** |
| 版权与许可证义务 | 保留 GPL-3.0；保留 Ketamine / neonmodder123 / skadz108 的来源说明（见 `THIRD_PARTY_NOTICES.md` §3）。Ketamine 本身为 GPL-3.0，但其 Respring 实现致谢了无许可证的 NeoSpring，改编链路因此缺乏可验证授权 |
| 仍需人工确认 | 建议确认改编依据的上游确切提交（低优先级）。重新集成须满足来源清楚、许可兼容、可证明有权再许可，并经独立审计与测试 |

## 4. NeoSpring — 改编（⚠️ 无许可证声明，需人工决定）

| 项目 | 内容 |
|---|---|
| 作者 / 组织 | rooootdev |
| GitHub | https://github.com/rooootdev/neospring |
| 使用的版本 / 提交 | 默认分支 `main`，最后推送 2026-06-13 |
| 许可证 | **无许可证声明**（2026-11-14 核实：GitHub API `/license` 返回 404；递归文件树确认仓库内无任何 `LICENSE` 文件；`neospring/neospring.swift` 与 `neospring/respring.swift` 只有 Xcode 文件头，无许可证头） |
| 证据来源 | https://github.com/rooootdev/neospring（仓库内容 + 递归文件树）；README 仅致谢："skadz … Ported neon's respring method to swift / neon … Came up with the respring method" |
| LilaShift 对应功能 | Respring（已暂停移除，2026-11-14；与 Ketamine 同一技术链路） |
| 对应源码文件 | `GestaltX/NeoSpringView.swift`（已删除，2026-11-14；原头部曾注明 NeoSpring 项目链接，未声明其许可证，因为它没有声明许可证） |
| 使用关系 | **已暂停（改编已移除，2026-11-14，用户决定方案 c）**：原为**改编**（技术来源）——注意：无许可证即默认保留所有权利，改编的法律依据不足，故整段实现移除 |
| 主要修改 | 同 Ketamine 条目（上游 GestaltX 的改编；已随文件删除而移除） |
| 是否打包进入 IPA | **否（2026-11-14 起不再打包）** |
| 版权与许可证义务 | **已处理（移除）**：无许可证可遵循，不得虚构一个许可证。2026-11-14 用户决定方案 (c)，改编实现已全部移除，不再随 IPA 分发。`THIRD_PARTY_NOTICES.md` §3 与本条记录暂停原因与版权链；重新集成须先获得有效授权并经独立审计与测试 |
| 仍需人工确认 | **已决定（2026-11-14，用户选方案 c：移除/替换）**。实现已移除；`NeoSpringView.swift` 已删除，Respring 操作改为手动重启提示。版权链（已核实，见下）：neonmodder123（发明 WebKit 注销方法；无可定位的带许可证公开实现，仅下游项目致谢）→ skadz108（移植为 Swift；无可定位的带许可证公开实现，仅下游项目致谢）→ rooootdev/neospring（无许可证声明）→ Nouvborne/Ketamine（GPL-3.0，其 `Ketamine/Views/NeoSpringView.swift` 与 `Ketamine/Models/RespringHelper.swift` 实现同一技术，README 致谢 rooootdev/NeoSpring）→ huamidev/GestaltX 改编（`GestaltX/NeoSpringView.swift`，2026-11-09）→ LilaShift 继承。无许可证环节（NeoSpring）使整条改编链路缺乏可验证授权 |

## 5. LCSign — 设计参考

| 项目 | 内容 |
|---|---|
| 作者 / 组织 | huamidev（与 GestaltX 同一作者） |
| 网址 | https://sign.lc（网站，非 GitHub 仓库） |
| 使用的版本 / 提交 | 不适用（网站服务；参考的是其 `LCEntitlementsReader` 的实现思路） |
| 许可证 | **无公开的开源许可证声明**（2026-11-14 核实：sign.lc 为 Next.js 网站；其 `/agreement`（2026-04-25）§5 称应用的标识、界面设计、原创代码著作权归开发者本人所有，未经书面授权不得复制、修改、转载或用于商业用途；第三方开源组件遵循各自协议，完整列表载于应用内"关于 → 开源许可证"。即 LCSign 本身为专有条款，无代码许可授予） |
| 证据来源 | https://sign.lc；https://sign.lc/agreement §5 |
| LilaShift 对应功能 | 运行时授权读取（App Group 容器解析）、签名权限检测 |
| 对应源码文件 | `GestaltX/GXEntitlementsReader.h`、`.m`（重新实现；头部已注明来源 URL 与"无公开许可证、不作断言"） |
| 使用关系 | **设计参考**（思路借鉴，代码重新实现；未打包 LCSign 代码） |
| 主要修改 | GestaltX 增加严格的 Mach-O 边界检查与有效的 SecTask 查找 |
| 是否打包进入 IPA | 否（仅设计思路；实现代码是 GestaltX 自己的） |
| 版权与许可证义务 | 不复制 LCSign 代码；注明来源；不为其断言任何许可证。GPL 标签仅覆盖 GestaltX 自己的重新实现（同一作者 huamidev），这一点已在文件头写明 |
| 仍需人工确认 | 否 |

## 6. Erosion-CN — 设计参考 + 复用数据

| 项目 | 内容 |
|---|---|
| 作者 / 组织 | Kianuni |
| GitHub | https://github.com/Kianuni/Erosion-CN |
| 使用的版本 / 提交 | 默认分支 `main`，最后推送 2026-11-14；六项改进于 2026-11-13 前后对照当时版本重新实现；数据表转录自当时的公开内容 |
| 许可证 | **GPL-3.0**（仓库 `LICENSE` + GitHub 标注一致） |
| 证据来源 | https://github.com/Kianuni/Erosion-CN/blob/main/LICENSE |
| LilaShift 对应功能 | Apple Intelligence 体检、安全写入、CacheUUID 发现、监管机型映射、原生 AI 设备清单、音频智能/个人翻译插槽基线 |
| 对应源码文件 | `GestaltX/AIReadinessCheckup.swift`（设计参考：`AppleIntelligenceCheckupCard` 思路）、`GestaltX/DevicePlistWriter.swift`（设计参考：`writeFileAtomically` 思路——仅名字；本实现为原位 pwrite，不作原子性声明）、`GestaltX/GXMobileGestaltImage.m`（设计参考：`MGImageReader` 的 `__cfstring` 遍历）、`GestaltX/USRegulatoryModelMapping.swift`（复用数据：`usRegulatoryModelNumber` 的 A-number 对照表，逐值转录）、`GestaltX/DeviceAIEligibility.swift`（复用数据：`isAppleIntellHD` 的原生 AI 设备清单 + iPhone 18 Pro Max / iPhone 15 Pro Max iOS 27 真机探针的插槽基线） |
| 使用关系 | **设计参考 + 复用数据**（未逐字复制代码；六项改进为重新实现：写入加固、运行时动态偏移解析、Diff 预览、双金库备份、地区模式、AI 四要素体检） |
| 主要修改 | 写入改为原位 pwrite + `F_FULLFSYNC` + 全量回读 + 原位回滚（不作原子性声明）；地区模式收敛为一键解锁只改 10 项（不采用 Erosion-CN 的完整美版模式）；Full US 保留为明确的可选模式（遵循其关于国行双实体卡 + eSIM 硬件冲突的警告） |
| 是否打包进入 IPA | 否（代码未打包；转录的数据表随 App 分发） |
| 版权与许可证义务 | GPL-3.0（LilaShift 本身即 GPL-3.0，同许可证下复用）；保留 Kianuni 署名与来源说明（文件头 + `THIRD_PARTY_NOTICES.md` §5） |
| 仍需人工确认 | 否 |

## 7. Erosion — 设计参考

| 项目 | 内容 |
|---|---|
| 作者 / 组织 | lunginspector / jailbreak.party 及贡献者 |
| GitHub | https://github.com/jailbreakdotparty/Erosion |
| 使用的版本 / 提交 | 默认分支 `main`，最后推送 2026-11-14 |
| 许可证 | **GPL-3.0**（仓库 `LICENSE`） |
| 证据来源 | https://github.com/jailbreakdotparty/Erosion/blob/main/LICENSE |
| LilaShift 对应功能 | 壁纸描述符布局与 PosterBoard 目标（`.tendies` 描述符） |
| 对应源码文件 | `GestaltX/CustomizationThemes.swift`、`GestaltX/GXCustomizationAccess.m`（仅遵循描述符约定；头部已补 URL） |
| 使用关系 | **设计参考**（未复制代码；GestaltX 自有原生界面、有界压缩包校验、运行时容器身份检查、隔离的壁纸归属记录、已验证写入与原始文件恢复） |
| 主要修改 | 无代码移植；仅参考描述符布局与目标命名 |
| 是否打包进入 IPA | 否 |
| 版权与许可证义务 | GPL-3.0；保留来源说明 |
| 仍需人工确认 | 否 |

## 8. Gester — 设计参考

| 项目 | 内容 |
|---|---|
| 作者 / 组织 | sasobhabha；版权 (c) 2026 KAMUI contributors |
| GitHub | https://github.com/sasobhabha/Gester |
| 使用的版本 / 提交 | 默认分支 `main`，最后推送 2026-11-09 |
| 许可证 | **MIT**（仓库 `LICENSE`；"MIT License / Copyright (c) 2026 KAMUI contributors"；随 App 分发的 `Gester-MIT.txt` 与上游逐字节相同） |
| 证据来源 | https://github.com/sasobhabha/Gester/blob/main/LICENSE |
| LilaShift 对应功能 | PosterBoard 描述符提供者、标识符再生、PosterBoard 刷新标志（`PBF_RESET_FILE_PROTECTIONS`） |
| 对应源码文件 | `GestaltX/CustomizationStore.swift`（刷新标志）、`GestaltX/CustomizationThemes.swift`、`GestaltX/GXCustomizationAccess.m`（仅遵循键名与描述符约定；头部已补 URL） |
| 使用关系 | **设计参考**（未复制代码；仅参考键名与描述符约定） |
| 主要修改 | 无代码移植。另注意：Gester 的 class-2 无 App Group 回退（27.2 路径）**默认关闭**，不得作为默认路径启用（其 README 明确说明该路径可能导致应用被终止）；其 class 7 symlink 策略（27.2 可用路径）仅作为未来研究候选，未并入写路径 |
| 是否打包进入 IPA | 否 |
| 版权与许可证义务 | MIT（保留版权声明即可；全文随 App 分发于 `Gester-MIT.txt`） |
| 仍需人工确认 | 否 |

## 9. ZIPFoundation — 直接集成（库）

| 项目 | 内容 |
|---|---|
| 作者 / 组织 | Thomas Zoechling |
| GitHub | https://github.com/weichsel/ZIPFoundation |
| 使用的版本 / 提交 | **0.9.20**（精确版本；`project.pbxproj` 的 `requirement = {kind = exactVersion; version = 0.9.20; }` 与 `Package.resolved` 一致，revision `22787ffb59de99e5dc1fbfe80b19c97a904ad48d`） |
| 许可证 | **MIT**（仓库 `LICENSE`，默认分支 `development`；"MIT License / Copyright (c) 2017-2026 Thomas Zoechling"） |
| 证据来源 | https://github.com/weichsel/ZIPFoundation/blob/development/LICENSE |
| LilaShift 对应功能 | ZIP 压缩包读取与解压（壁纸包导入） |
| 对应源码文件 | `GestaltX/CustomizationFiles.swift`（`import ZIPFoundation`；头部已注明版本与 MIT）；Swift Package 依赖 |
| 使用关系 | **直接集成**（Swift Package 链接的库） |
| 主要修改 | 无修改 |
| 是否打包进入 IPA | 是（链接进 App） |
| 版权与许可证义务 | MIT（保留版权声明；全文随 App 分发于 `ZIPFoundation-MIT.txt`，2026-11-14 已更新版权年份 2017-2025 → 2017-2026，现与上游逐字节相同） |
| 仍需人工确认 | 否 |

## 10. Primer Octicons — 直接集成（资源）

| 项目 | 内容 |
|---|---|
| 作者 / 组织 | GitHub Inc. |
| GitHub | https://github.com/primer/octicons |
| 使用的版本 / 提交 | 默认分支 `main`，最后推送 2026-11-06；使用 `icons/mark-github-16.svg` |
| 许可证 | **MIT**（仓库 `LICENSE`；"MIT License / Copyright (c) 2026 GitHub Inc."；README §License："Code License: MIT / Applies to all other files"） |
| 证据来源 | https://github.com/primer/octicons/blob/main/LICENSE |
| LilaShift 对应功能 | 关于页的 GitHub 图标 |
| 对应源码文件 | `GestaltX/Assets.xcassets/GitHubMark.imageset/GitHubMark.svg`（随 App 打包的资源） |
| 使用关系 | **直接集成**（资源文件） |
| 主要修改 | 无修改 |
| 是否打包进入 IPA | 是（图片资源） |
| 版权与许可证义务 | MIT（全文随 App 分发于 `Primer-Octicons-MIT.txt`，与上游逐字节相同）；**商标另计**：GitHub 名称与标志仍为 GitHub 商标，使用须遵循 GitHub logo 指南；`THIRD_PARTY_NOTICES.md` 已载明该商标声明。未修改的 UI 归属用途无需额外动作 |
| 仍需人工确认 | 否（未修改的 UI 归属用途；若未来改变标志用法须重新确认 logo 指南） |

## 11. MGKeys — 研究参考

| 项目 | 内容 |
|---|---|
| 作者 / 组织 | PoomSmart |
| GitHub | https://github.com/PoomSmart/MGKeys |
| 使用的版本 / 提交 | 默认分支 `master`，最后推送 2026-11-01；键名数据基于 iOS 27.2 |
| 许可证 | **MIT**（仓库 `LICENSE`；"MIT License / Copyright (c) 2020 - 2026 PoomSmart"） |
| 证据来源 | https://github.com/PoomSmart/MGKeys/blob/master/LICENSE |
| LilaShift 对应功能 | MobileGestalt 公开键映射对照（预设目录与能力表的键名核对） |
| 对应源码文件 | `GestaltX/Capabilities.swift`、`GestaltX/PresetCatalog.swift`（仅在注释/证据文本中引用对照关系；头部已补 URL 与许可证） |
| 使用关系 | **研究参考**（键名对照，未复制代码或数据；其 Python 生成脚本为离线研究工具，不进入 App） |
| 主要修改 | 无代码或数据移植。未来若生成 Swift 键名表/版本覆盖表（Tier 1 计划），须按 MIT 保留署名，且只纳入已用键子集 |
| 是否打包进入 IPA | 否 |
| 版权与许可证义务 | MIT（保留版权声明即可）；仅作参考时无分发义务 |
| 仍需人工确认 | 否 |

## 12. Nugget — 研究参考（AGPL-3.0，禁止移植）

| 项目 | 内容 |
|---|---|
| 作者 / 组织 | leminlimez |
| GitHub | https://github.com/leminlimez/Nugget |
| 使用的版本 / 提交 | 默认分支 `main`，最后推送 2026-09-24 |
| 许可证 | **AGPL-3.0**（仓库 `LICENSE`） |
| 证据来源 | https://github.com/leminlimez/Nugget/blob/main/LICENSE；README 警告（第 10–11 行）："DO NOT USE THIS ON iOS 27! It will most likely result in data loss. Apple has patched the partial restore method that Nugget uses." |
| LilaShift 对应功能 | 功能组织方式与交互设计参考（分类、搜索、筛选；"改什么、改成什么、有什么风险"的呈现） |
| 对应源码文件 | `GestaltX/Capabilities.swift`、`GestaltX/PresetCatalog.swift`（仅在注释/证据文本中引用对照关系） |
| 使用关系 | **研究参考**（仅设计参考；**未移植任何代码**——已用代码标识符检索验证：除归属注释与测试断言外，无 Nugget 代码标识符） |
| 主要修改 | 无。特别注意：**不得移植其恢复代码**——其备份恢复法在 iOS 27 上已失效（README 警告可能导致数据丢失），且 AGPL-3.0 移植会触发整体 AGPL 义务（网络服务也要开源），与现有 GPL-3.0 授权体系冲突。LilaShift 的恢复是文件级（原位写 + 备份 + 回读验证 + 原位回滚），与 Nugget 的方法不同 |
| 是否打包进入 IPA | 否 |
| 版权与许可证义务 | AGPL-3.0：仅作设计参考时无义务；**一旦移植代码即触发 AGPL 义务**。注明来源不等于获得使用许可 |
| 仍需人工确认 | 否（只要坚持不移植） |

## 13. mond — 研究参考（AGPL-3.0，禁止移植）

| 项目 | 内容 |
|---|---|
| 作者 / 组织 | rooootdev |
| GitHub | https://github.com/rooootdev/mond |
| 使用的版本 / 提交 | 默认分支 `main`，最后推送 2026-11-11 |
| 许可证 | **AGPL-3.0**（仓库 `LICENSE`） |
| 证据来源 | https://github.com/rooootdev/mond/blob/main/LICENSE；README 版本支持表：iOS 27.0 dev beta 1–4 支持，dev beta ≥ 5 与 public beta ≥ 3 不支持（注意 README 标题行 "Edit MobileGestalt on iOS 26.0 - 26.7.2 / 27.2!" 与其版本表矛盾，以版本表为准） |
| LilaShift 对应功能 | MobileGestalt 键映射对照 |
| 对应源码文件 | `GestaltX/Capabilities.swift`、`GestaltX/PresetCatalog.swift`（仅在注释/证据文本中引用对照关系） |
| 使用关系 | **研究参考**（仅键名对照；**未移植任何代码**——已用代码标识符检索验证） |
| 主要修改 | 无 |
| 是否打包进入 IPA | 否 |
| 版权与许可证义务 | AGPL-3.0：仅作参考时无义务；**一旦移植代码即触发 AGPL 义务**。注明来源不等于获得使用许可 |
| 仍需人工确认 | 否（只要坚持不移植） |

## 14. GestaltEdit — 研究参考（许可证已更正）

| 项目 | 内容 |
|---|---|
| 作者 / 组织 | frs0n |
| GitHub | https://github.com/frs0n/GestaltEdit |
| 使用的版本 / 提交 | 默认分支 `main`，最后推送 2026-11-13 |
| 许可证 | **GPL-3.0-or-later**（当前；仓库 `LICENSE` 为 GPL v3 文本；README §License："[GNU General Public License v3.0 or later](LICENSE)"，徽章 `GPL-3.0-or-later`）。**许可证历史（已逐提交核实）**：MIT（2026-08-11 首次公开，`9d73f4a`）→ PolyForm Noncommercial 1.0.0（2026-08-20，`bca57fd`，"Relicense under PolyForm Noncommercial 1.0.0; trim READMEs"）→ GPL v3（2026-11-09，`ed8192e`，"Replace bad_query with worse_query"，该提交同时改动 `LICENSE`；与采用 GPL 许可的 worse_query 一致，属作者主动重新许可） |
| 证据来源 | https://github.com/frs0n/GestaltEdit/blob/main/LICENSE；`raw.githubusercontent.com/frs0n/GestaltEdit/<sha>/LICENSE`（逐提交核实）；`api.github.com/repos/frs0n/GestaltEdit/commits?path=LICENSE` |
| LilaShift 对应功能 | 工作流程参考（MobileGestalt 编辑流程） |
| 对应源码文件 | 无（仅在 `GestaltX/AboutView.swift` 的致谢列表中引用） |
| 使用关系 | **研究参考**（仅工作流程参考；未包含任何代码） |
| 主要修改 | 无。**更正说明**：本仓库此前的声明（PolyForm Noncommercial 1.0.0）仅在 2026-08-20 至 2026-11-09 期间为真，现已过时；2026-11-14 已更正为 GPL-3.0-or-later 并记录历史。非商业限制已不再适用 |
| 是否打包进入 IPA | 否 |
| 版权与许可证义务 | GPL-3.0-or-later：仅作参考时无义务 |
| 仍需人工确认 | 否（许可证已核实；若未来要移植其代码，须按 GPL-3.0-or-later 处理） |

## 15. SnapshotTesting — 测试工具（不随 IPA 分发）

| 项目 | 内容 |
|---|---|
| 作者 / 组织 | Point-Free, Inc.（pointfreeco） |
| GitHub | https://github.com/pointfreeco/swift-snapshot-testing |
| 使用的版本 / 提交 | **1.19.7**（精确版本；`project.pbxproj` 的 `requirement = {kind = exactVersion; version = 1.19.7; }`；测试 target 专用） |
| 许可证 | **MIT**（仓库 `LICENSE`；"MIT License / Copyright (c) 2019 Point-Free, Inc."） |
| 证据来源 | https://github.com/pointfreeco/swift-snapshot-testing/blob/main/LICENSE |
| LilaShift 对应功能 | SwiftUI 关键卡片的快照回归测试（预设目录、智能故障诊断、个性化中心、系统健康评分） |
| 对应源码文件 | `tests/ViewSnapshotTests.swift` 等（测试 target；`GestaltXTests/__Snapshots__/` 参考图随代码入库） |
| 使用关系 | **测试工具**（SPM 依赖，仅测试 target；不增加 App 体积） |
| 主要修改 | 无。快照参考图须在与 CI 相同的模拟器/Xcode 上录制；UI 改动须有意更新参考图 |
| 是否打包进入 IPA | 否 |
| 版权与许可证义务 | MIT（保留版权声明即可）；测试工具不随 App 分发，许可证文本不打包进 App（上游链接见上） |
| 仍需人工确认 | **是——构建清单问题（非许可证问题）**：已提交的 `Package.resolved` 仅固定了 ZIPFoundation 0.9.20，**未列出 SnapshotTesting**，而 `project.pbxproj` 要求其精确版本 1.19.7。须在有 Xcode 的环境运行 `xcodebuild -resolvePackageDependencies` 重新生成并提交；在此之前 `scripts/check-licenses.py` 会报出该差异作为警告 |

## 16. SwiftLint — 构建工具（不随 IPA 分发）

| 项目 | 内容 |
|---|---|
| 作者 / 组织 | Realm Inc. / The SwiftLint Contributors |
| GitHub | https://github.com/realm/SwiftLint |
| 使用的版本 / 提交 | CI 经 Homebrew 安装（`.github/workflows/swiftlint.yml`）；规则集为仓库根 `.swiftlint.yml`（最小规则集，仅启用当前代码已通过的规则） |
| 许可证 | **MIT**（仓库 `LICENSE`；"The MIT License (MIT) / Copyright (c) 2025 The SwiftLint Contributors"） |
| 证据来源 | https://github.com/realm/SwiftLint/blob/main/LICENSE |
| LilaShift 对应功能 | Swift 代码风格与静态检查（CI 非阻塞先行） |
| 对应源码文件 | `.swiftlint.yml`（配置）；`.github/workflows/swiftlint.yml`（CI） |
| 使用关系 | **构建工具**（不进入 App） |
| 主要修改 | 无。规则收紧须逐步进行，不得为通过检查而一次性重构代码 |
| 是否打包进入 IPA | 否 |
| 版权与许可证义务 | MIT；工具不随 App 分发 |
| 仍需人工确认 | 否 |

---

## 已调研、未集成（仅作记录，防止未来误认）

| 项目 | 许可证 | 状态 |
|---|---|---|
| WorkPlot（gievano/WorkPlot） | GPL-3.0 | 设计参考：Preset Lab、Session Log、字段编辑器的十六进制查看。**写实现仅在 iOS 27 beta 1–4 验证，正式版未验证，不得移植** |
| idevice（jkcoxson/idevice） | MIT | Tier 2 研究：Rust 设备通信库；上游 GestaltX 1.0.8 已 vendored，LilaShift 的 1.0.8 rebase 被阻塞，暂未引入 |
| libimobiledevice | LGPL-2.1-or-later | Tier 2 研究：桌面端设备通信（动态链接）；不编进iOS App |
| pymobiledevice3（doronz88/pymobiledevice3） | GPL-3.0 | 测试辅助工具（桌面端脚本）；不进 App |
| SideStore / AltStore / LiveContainer | AGPL-3.0 | 仅参考设计，**不得移植代码** |
| Feather / zsign | GPL-3.0 / MIT | 签名/安装研究（属 LilaShift 2.0 另一项目线）；不在本 App 树内 |
| Leaflet / gcoord | — | 不在本树内（属 WLOC 网页工具）；不在此列出 |

---

## 已知问题（需人工跟进）

1. **NeoSpring 无许可证**（见 §4）：**已决定并处理（2026-11-14，用户选方案 c：移除/替换）**。改编的法律依据不足，`GestaltX/NeoSpringView.swift` 已删除，Respring 操作改为手动重启提示，不再随 IPA 分发。重新集成须先获得有效授权并经独立审计与测试。决定前不得新增对该技术的依赖。
2. **`Package.resolved` 缺少 SnapshotTesting 的固定版本**（见 §15）：须在 Xcode 环境重新生成。
3. **worse_query 与 Ketamine 的引入提交尚未核实**（见 §2、§3）：低优先级，不影响许可证结论（文件自带完整声明）。
4. **fa 语言的 32 个新增本地化键未经母语审校**（3.0 集成遗留）；本次新增的 21 个关于页键的 8 语种翻译同样未经母语审校，测试只校验格式与脚本，不校验翻译质量。
