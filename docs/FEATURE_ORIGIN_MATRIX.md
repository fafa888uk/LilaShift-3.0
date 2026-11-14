# LilaShift 3.0 — 功能来源映射表（Feature Origin Matrix）

> 核实日期：2026-11-14。每一项功能按来源分为三类：
> - **原始代码**：上游 GestaltX（huamidev）已有，LilaShift 继承。
> - **第三方参考成果**：参考第三方项目的设计、数据或代码改编而来（来源见
>   `docs/OPEN_SOURCE_REFERENCES.md`，文件头亦有注明）。
> - **LilaShift 新增实现**：LilaShift 自行开发（维护者 @steam8871）。
>
> "未实现"与"已实现"严格区分：凡写"已实现"的功能均已在源码中存在并有测试
> 或 CI 覆盖；凡写"未实现 / 计划中"的功能均未写成已完成。
> 完整许可证与证据见 `docs/OPEN_SOURCE_REFERENCES.md` 与
> `THIRD_PARTY_NOTICES.md`。

---

## 1. MobileGestalt 设备读取

| 方面 | 来源 |
|---|---|
| 基础读取（`GXMobileGestaltImage`、`GestaltManager`） | **原始代码**（上游 GestaltX） |
| 沙盒逃逸（读/写的前提） | **第三方参考成果**：worse_query（forcequitOS）**直接集成**，GPL-3.0-or-later，原样引入（`GestaltX/worse_query.m/.h`） |
| CacheUUID 发现（`__cfstring` 遍历） | **第三方参考成果**：Erosion-CN 的 `MGImageReader` 思路，**设计参考**后重新实现（`GestaltX/GXMobileGestaltImage.m`） |
| 运行时动态偏移解析（47-bit PAC mask，硬编码兜底有门控） | **LilaShift 新增实现**（Erosion-CN 六项改进之一，重新实现） |
| 容器身份发现（fsgetpath 研究） | **第三方参考成果**：forcequitOS 的 fsgetpath 研究，**设计参考**（`GestaltX/GXCustomizationAccess.m`） |

## 2. 国行一键解锁

| 方面 | 来源 |
|---|---|
| 一键暂存 9 项（eSIM 两开关、地区码 US、6 项 AI 能力） | **LilaShift 新增实现**（P0–P1；9 项的定义为 LilaShift 产品规则） |
| 暂存模型、预览、应用流程 | **原始代码**（上游 GestaltX 的暂存/事务模型）+ **LilaShift 新增实现**（一键解锁规则、守卫） |
| eSIM 缓存布局校验（无法验证则整组停止并说明原因） | **LilaShift 新增实现** |
| 地区模式选择 | **第三方参考成果**：Erosion-CN 的地区模式思路，**设计参考**；已收敛为"一键解锁只改 9 项"，不采用其完整美版模式 |

## 3. Apple Intelligence 检测

| 方面 | 来源 |
|---|---|
| 原生 AI 设备清单、插槽基线（#178/#266） | **第三方参考成果**：Erosion-CN 的 `isAppleIntellHD` 与真机探针数据，**复用数据**（逐值转录，`GestaltX/DeviceAIEligibility.swift`） |
| AI 四要素体检 + 冲突守卫 | **第三方参考成果**：Erosion-CN 的 `AppleIntelligenceCheckupCard` 思路，**设计参考**后重新实现（`GestaltX/AIReadinessCheckup.swift`）；**LilaShift 新增实现**：六态判定（原生/已配置/可改/硬件不支持/未知/冲突）与 P0 守卫逻辑 |
| 键名对照 | **第三方参考成果**：MGKeys / Nugget / mond，**研究参考**（仅对照键名，未复制代码或数据） |

## 4. eSIM 与地区

| 方面 | 来源 |
|---|---|
| eSIM 开关（green-tea / not-green-tea）与地区码 | **LilaShift 新增实现**（一键解锁 9 项的一部分；槽位为运行时动态解析） |
| 美国监管机型 A-number 对照表 | **第三方参考成果**：Erosion-CN 的 `usRegulatoryModelNumber`，**复用数据**（逐值转录，`GestaltX/USRegulatoryModelMapping.swift`） |
| 国行双实体卡 + eSIM 硬件冲突警告 | **第三方参考成果**：Erosion-CN 的说明，**设计参考**（Full US 保留为明确的可选模式，`GestaltX/Capabilities.swift`） |

## 5. 安全写入

| 方面 | 来源 |
|---|---|
| 原位 pwrite + `F_FULLFSYNC` + 全量回读 + 原位回滚 | **LilaShift 新增实现**（P0 加固；Erosion-CN 六项改进之一，重新实现） |
| 写入思路（`writeFileAtomically` 的名字与意图） | **第三方参考成果**：Erosion-CN，**设计参考**（`GestaltX/DevicePlistWriter.swift`；注意：本实现为原位写入，**不作原子性声明**，与名字暗示的不同） |
| 写前自动备份、写后读回验证 | **LilaShift 新增实现**（P0） |
| 写盘不可见时明说（不伪造成功） | **LilaShift 新增实现**（P0 原则；WorkPlot 的同名设计为独立参考，未移植其代码） |

## 6. 备份与恢复

| 方面 | 来源 |
|---|---|
| 备份/事务基础 | **原始代码**（上游 GestaltX） |
| 双金库备份（系统金库 `.gestaltx_factory_vault.plist` + SHA-256） | **LilaShift 新增实现**（P0；Erosion-CN 六项改进之一，重新实现） |
| 历史记录、逐项恢复、恢复预览、二次确认 | **LilaShift 新增实现**（P0 Restore Intelligence + 3.0 `HistoryRestoreSummary.swift`） |
| 首次记录值 ≠ 出厂原始值的诚实标注 | **LilaShift 新增实现**（P0） |
| Nugget 的备份恢复法 | **未采用**：其方法在 iOS 27 上已失效（上游 README 警告可能导致数据丢失），且为 AGPL-3.0，**禁止移植** |

## 7. 设备指纹

| 方面 | 来源 |
|---|---|
| 设备能力指纹（v1 + SHA-256；变化使已记录的支持范围失效） | **LilaShift 新增实现**（P1） |
| 键名与版本覆盖数据 | **第三方参考成果**：MGKeys，**研究参考**（计划中的 Tier 1 数据库将复用其键名表与版本覆盖表，MIT，需署名；当前版本尚未生成该表——**未实现**，见下） |
| 逐机型/逐 iOS 版本兼容性矩阵、slot=-1 键清单、纯物理硬件限制清单 | **计划中，未实现**（Erosion-CN FAQ 的兼容性知识，**设计参考**，Tier 1 待做） |

## 8. 智能兼容性诊断

| 方面 | 来源 |
|---|---|
| 智能故障诊断（20 条规则；未知原因报"无法确定"，不猜测） | **LilaShift 新增实现**（P2） |
| 统一兼容性状态模型（原生支持 / 可修改 / 已启用 / 已暂存 / 需要重启 / 未验证 / 不支持 / 读取失败） | **LilaShift 新增实现**（3.0 `GestaltX/CompatibilityStatus.swift`） |
| 兼容性知识（逐机型/逐版本矩阵、27.3 beta 1 国行策略拦截警告） | **第三方参考成果**：Erosion-CN FAQ，**设计参考**（知识已结构化进兼容性模型；完整矩阵仍在扩展中） |
| 诊断日志格式（一键只读检查、策略 → 结果 → 失败原因） | **第三方参考成果**：Gester 的 Run Diagnostics 与 `bqtool.log`，**设计参考**（Tier 1 待补齐） |

## 9. 系统健康评分

| 方面 | 来源 |
|---|---|
| 系统健康评分（4 个维度；总分上限 99，永不 100；未读取时全未知） | **LilaShift 新增实现**（P1） |
| 电池健康/循环/温度（仅公开 UIDevice；健康/循环/容量明确报不可用） | **LilaShift 新增实现**（P4 诊断扩展；Erosion-CN 的电池诊断为 Tier 2 待移植项，**未实现**） |

## 10. 智能预设

| 方面 | 来源 |
|---|---|
| 预设目录（40 项：35 个能力项 + WAPI + 机型编号 + 3 个组合） | **LilaShift 新增实现**（P3；每项含中文名、说明、适用范围、最低系统、风险等级与具体机制、恢复方式、可追溯证据） |
| 智能计划（仅作计划，不连接应用） | **LilaShift 新增实现**（P3；组合为计划，应用路径 deliberately 未连接） |
| 自定义预设（创建/编辑/删除） | **LilaShift 新增实现**（P4；同样仅作计划） |
| 键映射对照 | **第三方参考成果**：MGKeys / Nugget / mond，**研究参考**（仅对照，未复制代码或数据） |
| 预设保存/复用模式（Preset Lab） | **第三方参考成果**：WorkPlot 的 Preset Lab，**设计参考**（Tier 3 待做；**未移植其写实现**，其写实现仅在 iOS 27 beta 1–4 验证） |
| 功能分组/搜索/筛选的组织方式 | **第三方参考成果**：Nugget 的功能分组，**设计参考**（仅组织方式，不抄代码） |

## 11. 应用启动图管理

| 方面 | 来源 |
|---|---|
| 启动图预览（图片校验、裁剪、圆角预览、名称编辑、撤销、SHA-256 本地草稿） | **LilaShift 新增实现**（PR #3 App Appearance；明确为"仅预览"，能力恒为 unknown） |
| 个性化基础设施（容器访问、文件导入） | **原始代码**（上游 GestaltX 的个性化基础设施）+ **LilaShift 新增实现**（导入/验证/应用/备份/恢复流程；`launchImage` / `lockScreenText` 的应用处理器须先补上——**已知缺口，未实现**） |

## 12. 壁纸个性化

| 方面 | 来源 |
|---|---|
| 壁纸描述符布局与 PosterBoard 目标（`.tendies`） | **第三方参考成果**：Erosion，**设计参考**（`GestaltX/CustomizationThemes.swift`、`GXCustomizationAccess.m`）；Gester，**设计参考**（描述符提供者、标识符再生、刷新标志） |
| 壁纸导入/验证/应用/备份/恢复 | **原始代码**（上游 GestaltX）+ **LilaShift 新增实现**（有界压缩包校验、运行时容器身份检查、隔离的壁纸归属记录、已验证写入与原始文件恢复） |
| ZIP 压缩包读取 | **第三方参考成果**：ZIPFoundation 0.9.20，**直接集成**（MIT，Swift Package 链接，`GestaltX/CustomizationFiles.swift`） |

## 13. Respring

| 方面 | 来源 |
|---|---|
| Respring 实现（WebKit 技术） | **已暂停并移除（2026-11-14）**：上游 GestaltX 的 `GestaltX/NeoSpringView.swift` 已删除；WebKit 注销技术不再随 App 分发 |
| 技术来源与版权链 | **第三方参考成果**：Ketamine（GPL-3.0）与 NeoSpring（**无许可证声明**）。版权链（已核实）：neonmodder123（发明 WebKit 注销方法）→ skadz108（移植为 Swift）→ rooootdev/neospring（无许可证声明）→ Nouvborne/Ketamine（GPL-3.0，致谢 NeoSpring）→ huamidev/GestaltX 改编（2026-11-09）→ LilaShift 继承。无许可证环节（NeoSpring）使改编缺乏可验证授权，故整段实现移除；见 `OPEN_SOURCE_REFERENCES.md` §3、§4 |
| 移除决定 | 用户决定（2026-11-14，方案 c：移除/替换）。未获有效授权前，不得把来源不明或授权不明确的 WebKit Respring 实现打包发布 |
| 替代实现 | **LilaShift 新增实现**：手动重启提示（Tools 页“Restart Device”按钮 + 弹窗说明），明确告知用户自行重启设备，绝不假装执行成功。不是改名、不是变量调整、不是重写相同代码 |
| 重新集成条件 | 若后续找到来源清楚、许可兼容且可证明有权再许可的实现，须经独立审计与测试后重新集成 |

## 14. 签名权限检测

| 方面 | 来源 |
|---|---|
| 运行时授权读取（App Group 容器解析） | **原始代码**（上游 GestaltX 的 `GXEntitlementsReader`，LilaShift 继承） |
| 授权读取思路 | **第三方参考成果**：LCSign 的 `LCEntitlementsReader`，**设计参考**（重新实现；LCSign 无公开许可证，不复制其代码） |
| 签名健康检查（TeamID、扩展 App Group、共享容器解析） | **LilaShift 新增实现**（Phase F `SigningHealthChecker` 结构；Gester 的动态 App Group 读取为**设计参考**，用于改善报错信息） |
| 铃声管理（App Audio Library）与设备配对 | **未实现**：在上游 GestaltX 1.0.8 中，LilaShift 的 1.0.8 rebase 被阻塞（20 个冲突），**暂未引入** |

## 15. SwiftUI 玻璃界面

| 方面 | 来源 |
|---|---|
| 浅紫 Liquid Glass 风格（背景 `#F6F3FF`、主紫 `#8652DC`、玻璃卡片） | **LilaShift 新增实现**（`GestaltX/LiquidGlass.swift`、`GlassTokens`；遵循 Apple 的 Liquid Glass 设计语言，非开源代码） |
| GitHub 图标 | **第三方参考成果**：Primer Octicons 的 GitHub 标志 SVG，**直接集成**（MIT；商标另计，见 `OPEN_SOURCE_REFERENCES.md` §10） |
| 界面基础 | **原始代码**（上游 GestaltX 的 SwiftUI 界面） |

## 16. LilaShift 3.0 新增模块

| 模块 | 来源 | 说明 |
|---|---|---|
| `GestaltX/DashboardV3.swift` | **LilaShift 新增实现** | 轻量可配置首页 + 稳定快捷排序（3.0 分支提交 `493d71c`） |
| `GestaltX/FeatureCatalog.swift`、`FeatureCatalogViews.swift` | **LilaShift 新增实现** | 53 项、11 分类的功能目录；单一排序规则；版本化 JSON + SHA-256 sidecar |
| `GestaltX/CompatibilityStatus.swift` | **LilaShift 新增实现** | 8 状态兼容性模型；`isOffered()` 仅对 `.modifiable` 返回真 |
| `GestaltX/HistoryRestoreSummary.swift` | **LilaShift 新增实现** | 统一历史与恢复视图；恢复预览清单；二次确认 |
| `GestaltX/HomeDiagnosticsCache.swift`、`HomeDiagnosticsSection.swift` | **LilaShift 新增实现** | 诊断计算缓存（后台算一次、只发变化值）+ 11 张诊断卡的二级页 |
| `GestaltX/HomeSorting.swift` | **LilaShift 新增实现** | 排序规则（预设、历史、修改字段）与测试 |
| `GestaltX/ContentView.swift`（3.0 路由） | **原始代码** + **LilaShift 新增实现** | 上游 ContentView 为基线；3.0 加入首页路由与旧工具页懒加载 |
| `tests/` 新增的 3.0 测试 | **LilaShift 新增实现** | 首页/目标快照、缓存失效、并发、导航可达、功能目录测试 |

---

## 未实现的功能（明确列出，防止误认）

| 功能 | 状态 | 来源/备注 |
|---|---|---|
| MGKeys 键名表与版本覆盖表（Swift 表） | 未实现（Tier 1） | MGKeys，MIT，需署名；只纳入已用键子集 |
| 完整兼容性矩阵（逐机型/逐版本） | 未实现（Tier 1） | Erosion-CN FAQ，设计参考 |
| 清除并重建缓存（纯净原厂基线） | 未实现（Tier 1） | Erosion-CN，GPL-3.0，需先有可信原厂备份 |
| 电池与崩溃诊断（真实读数） | 未实现（Tier 2） | Erosion-CN，GPL-3.0 |
| 应用存档备份、跨容器写操作 | 未实现（Tier 2，须单独评估权限与风险） | Erosion-CN，GPL-3.0 |
| 铃声管理、设备配对、桌面助手 | 未实现（Tier 2，依赖 1.0.8 rebase） | 上游 GestaltX 1.0.8 + idevice（MIT）/ libimobiledevice（LGPL-2.1） |
| iOS 27.2 逃逸（Gester class 7 symlink） | 研究中，未实现 | Gester，MIT；须先真机验证；class-2 无 App Group 回退保持默认关闭 |
| 自定义预设编辑器（Preset Lab 模式） | 未实现（Tier 3） | WorkPlot，设计参考；写实现用 LilaShift 自己的，不用 WorkPlot 的 beta-only 实现 |
| 完整中文功能数据库 | 未实现（Tier 3） | MGKeys 数据 + 人工编写中文条目 |
