# 更新日志

[English](CHANGELOG.md) | 简体中文

## [4.1.0] - 2026-11-18

正式版。基于分支 `feature/lilashift-4.0-quality-upgrade` 的 4.0.0 基线提交 `6c8c4aba` 加 Stage 13 功能批构建。应用内版本 `4.1.0`，构建号 `41000001`；IPA 文件 `LilaShift_4.1.0.ipa`（bundle `com.huami.gestultx`，最低 iOS `26.0`）。

### 新增（相对 4.0.0）
- App Audio Library：用自定义音频替换通知音，按上游 GestaltX v1.1.1 1:1 移植（GPL-3.0，已署名）。覆盖已在容器内露出通知音的 App；捕获指引（用于声音在 App 包内的应用）需要配对与设备连接，推迟到后续阶段——见 Stage 13 实施记录。
- 锁屏文字（目录集成）：系统设置页本身已在 4.0.0 中（按上游 GestaltX v1.0.6 1:1 移植）；Stage 13 新增目录指针条目（可在搜索与目录中发现）、版本哨兵门控（被封堵的版本现显示停留/降级指引而非误导性错误），并说明全局恢复不包含此项——须在「系统设置」页点还原。
- 上游 v1.1.1 全量对照中其余可移植项（对照表见 Stage 13 实施记录）。
- 日文 README（README_JA.md），由英文 README 翻译并适配至 4.1.0——包含 App Audio Library、锁屏文本条目与 iOS 27.3 beta 2 提示。初版翻译，待母语者校对。

### 注意
- 新功能适用于 iOS 27.0–27.3 beta 1。苹果已在 iOS 27.3 beta 2 中封堵底层机制，如需使用这些功能请勿升级超过 27.3 beta 1。

## [4.0.0] - 2026-11-18

正式版。基于分支 `feature/lilashift-4.0-quality-upgrade` 的提交 `7c6df01` 构建（代码基线；同分支随后还有一次仅改文档的版本一致性修复）。应用内版本 `4.0.0`，构建号 `40000001`；IPA 文件 `LilaShift_4.0.0.ipa`（bundle `com.huami.gestultx`，最低 iOS `26.0`）。

### 新增（相对 3.0.0）
- MG 实时监控与键值库（77 条种子键、版本哨兵、兼容性模型）。
- 高级备份与差异恢复（BackupEngine/RestoreEngine）。
- 智能诊断中心（DiagnosticsEngine，含修复建议与性能区）。
- 应用存档与缓存分析（沙盒合规 ZIP 存档；不做第三方应用备份）。
- 壁纸与个性化中心（WallpaperLibrary；无公开 API 可设系统壁纸或他人 App 启动图，「应用」指导出到相册加指引）。
- 性能优化（拨号盘导入/缩放、MG 键表搜索防抖、诊断缓存、PreviewImageCache、PerformanceMonitor；不编造指标，基线只写测量方法）。

### 已验证
- Run Swift Tests #429：744 执行、3 跳过、0 失败；Build IPA #431 绿；SwiftLint #178 绿；均在提交 `7c6df01` 上。

## [3.0.0-rc.1] - 预发布（非稳定版）

由 `feature/lilashift-3.0-dashboard` 分支构建，提交 `37c4a36`
（`37c4a368c73ec80654c8b395387abea9a24915f6`，包含 fix4 提交 `7020964`）。App 内版本号 `3.0.0`，build
`30000002`；IPA 文件 `LilaShift_3.0.0.ipa`（包名 `com.huami.gestultx`，
最低 iOS `26.0`）。`rc.1` 是发布/标签层面的命名；Xcode 工程里的
marketing version 仍为 `3.0.0`。

### 新增（相对 2.0 / 1.0.7）
- LilaShift 3.0 首页：轻量首页（真实设备读取与待应用更改状态）；53 项 11 分类的功能目录（40 个预设项 + 13 个页面项，版本化 JSON + SHA-256 sidecar 排序）；8 状态统一兼容性模型（`nativeSupported`、`modifiable`、`enabled`、`staged`、`needsRestart`、`unverified`、`unsupported`、`readFailed`）；带二次确认的历史恢复视图；诊断缓存（`HomeDiagnosticsCache`，11 张诊断卡移至二级页、`LazyVStack`、移除 iOS 26+ 阴影）。
- 本预发布文档：`README.md` / `README_ZH-CN.md` 重写为 3.0.0-rc.1 产品主页，`docs/` 下新增简体中文安装 / 使用 / 兼容性 / 备份还原 / 故障排查 / 功能 / FAQ 一步一步教程，以及 `COMMUNITY.md`、`SECURITY.md`、`CONTRIBUTING.md`。各安装方式的验证状态见 `docs/INSTALL_ZH-CN.md`。
- 开源审计（2026-11-14）：逐项来源记录 `docs/OPEN_SOURCE_REFERENCES.md`（16 个项目）与逐功能来源映射 `docs/FEATURE_ORIGIN_MATRIX.md`；关于页重建为开源贡献者中心；20 个文件完成版权头规范化；新增 `scripts/check-licenses.py` 与 Check Licenses 工作流。

### 修复
- AboutView 标题栏：3 处 `Section(L(...))` + `footer:` 写法没有对应的 SwiftUI 重载，现已改用显式 `header:` / `footer:` 视图（提交 `7020964`）。
- HomeDiagnosticsCache / 并发测试修复（提交 `7020964`）：测试夹具改用真实的 `GestaltKeys.*` 键，不再用字面 `"regionCode"` / `"productType"` 字符串；`LilaRecommendation` 相等比较忽略 `id` / `createdAt`，`DeviceFingerprint` 相等比较忽略 `recordedAt`（与摘要规则一致）；新增回归测试 `tests/DiagnosticsEquatableTests.swift`。
- `HomeDiagnosticsCache.swift` 已补 `import Combine`，`ObservableObject` / `@Published` 可在 CI 中解析（此前修复见 `0a429e9`）。

### 移除
- NeoSpring/Ketamine WebKit 注销实现已移除（删除 `GestaltX/NeoSpringView.swift`，2026-11-14）：NeoSpring 在任何地方均未声明许可证，因此不再随本版分发。改为手动重启设备提示，绝不假装自行重启 SpringBoard。

### 本 HEAD 已知缺口（2026-11-15，提交 `37c4a36`）
- **本版无真机验证。** 安装、eSIM 开通、Apple Intelligence 开通与还原均未在真机上为 3.0.0-rc.1 测试过。`docs/INSTALL_ZH-CN.md` 中无法从仓库核实的安装步骤均已标为待验证。
- **本提交的 CI 状态尚未在本日志中确认。** fix4 提交（`7020964`）落在上次记录的测试运行之后；发布前请先看 `README.md` 里的 workflow 徽章确认最新运行结果。此前记录：Tests #129 在整合前 HEAD（`096330e`）通过；Tests #137 与 IPA #138 在整合后 HEAD（`86e32b4`）失败（缺 `import Combine`，已修）。
- 8 张快照基线待 CI 渲染新图后重录（阴影移除与新增排序/隐藏 UI）；10 张新增 Phase H 快照参考在首次 CI 运行时录制，须在后续提交中提交。
- `Package.resolved` 只锁定了 ZIPFoundation，工程同时要求 SnapshotTesting 1.19.7——须在 Xcode 环境中运行 `xcodebuild -resolvePackageDependencies` 解决。
- 尚无真实 3.0.0-rc.1 构建的截图；此处不声称有。
- 写本文档时 `v3.0.0-rc.1` 标签与 GitHub Release 尚不存在，随预发布发布时创建。

## [Unreleased]

## [3.0.0] - 开发预览版（未正式发布）

> 已被上方的 [3.0.0-rc.1] 取代（针对当前 HEAD）。以下条目保留为 3.0 开发预览版的历史记录。

### 新增
- 全新 3.0 轻量首页：展示真实设备读取状态和待应用更改数量，避免首次打开即渲染所有复杂诊断卡。
- 将解锁、诊断、备份恢复、预设个性化分成独立的导航页面；旧版工具页仍可从「全部工具」进入，确保功能可回退。
- 首页快捷入口支持系统原生重新排序，设置保存在本机；自动修复旧版或异常排序数据。
- 新增首页排序单元测试，3.0 分支构建 IPA 和 XCTest 可通过 GitHub Actions 自动触发。
- 3.0 整合（C–I 阶段）：8 分区首页、53 项 11 分类的功能目录（统一排序规则，版本化 JSON + SHA-256 sidecar）、8 状态统一兼容性模型、带二次确认的历史恢复视图、诊断缓存（`HomeDiagnosticsCache`，11 张诊断卡移至二级页、`LazyVStack`、移除 iOS 26+ 阴影），Swift 测试函数共 356 个。
- 构建号 30000001 → 30000002；版本号保持 3.0.0。

### 新增（开源审计，2026-11-14）
- 开源审计：逐项来源记录见 `docs/OPEN_SOURCE_REFERENCES.md`（16 个项目），逐功能来源映射见 `docs/FEATURE_ORIGIN_MATRIX.md`。
- 关于页重建为开源贡献者中心：每个实际使用或参考的项目各为一条，含作者、使用关系、关键技术、许可证与源码链接；第三方许可证均来自 App 内置的真实文本；附完整源码链接与免责声明。
- 20 个实际使用或改编第三方代码的文件完成版权头规范化（SPDX + 原始来源 + 修改说明）；GestaltEdit 许可证由 PolyForm Noncommercial 1.0.0 更正为 GPL-3.0-or-later；ZIPFoundation MIT 文本更新为 2017-2026（与上游逐字节相同）。
- 新增许可证合规检查脚本 `scripts/check-licenses.py`（每次 IPA 构建时由 check-licenses 工作流运行）与 `tests/ThirdPartyNoticesTests.py` 中的许可证一致性测试。

### 移除（Respring 授权，2026-11-14）
- 移除 NeoSpring/Ketamine WebKit 注销实现（删除 `GestaltX/NeoSpringView.swift`；用户决定方案 c）。该技术无可验证授权：NeoSpring（rooootdev/neospring）在任何地方均未声明许可证。本构建不再包含任何注销代码。注销操作改为手动重启设备提示，绝不假装自行重启 SpringBoard。见 `docs/OPEN_SOURCE_REFERENCES.md` §3–§4。

### 待验证
- 整合后 3.0 分支的 GitHub Actions 构建：Tests #129 已在整合前 HEAD（096330e）通过；整合后 HEAD（86e32b4）的 Tests #137 与 IPA #138 因 `HomeDiagnosticsCache.swift` 缺少 `import Combine` 而失败（修复进行中）。真机性能尚未验证。
- 8 张快照基线待 CI 渲染新图后重录（阴影移除与新增排序/隐藏 UI）；10 张新增 Phase H 快照参考在首次 CI 运行时录制，须在后续提交中提交。
- NeoSpring 注销：已于 2026-11-14 决定并处理（用户选方案 c，移除/替换）；实现已删除，关于页将 Ketamine 与 NeoSpring 标记为已暂停。重新集成须先找到来源清楚、许可兼容的实现，并经独立审计与测试；见 `docs/OPEN_SOURCE_REFERENCES.md` §4。
- `Package.resolved` 只锁定了 ZIPFoundation，工程同时要求 SnapshotTesting 1.19.7——须在 Xcode 环境中运行 `xcodebuild -resolvePackageDependencies` 解决。



### 新增

- 新增 SnapshotTesting UI 回归测试，覆盖关键 SwiftUI 卡片（预设目录、智能故障诊断、个性化中心、系统健康评分——未读取与已填充两种状态，固定 390×844 布局、浅色特征），以及诊断卡片的确定性输入数据文本快照（电池未知/已知、连接未读取/已读取、固定目录的缓存条目）。诊断扩展卡片本身特意没有图片快照：其缓存区显示的是实时容器大小，会随测试执行顺序变化。快照参考在首次 CI 运行时录制（`record: .missing`），存入 `tests/__Snapshots__/ViewSnapshotTests/`，须在后续提交中提交；详见 `docs/SNAPSHOT_TESTING.md`。
- 新增 SwiftLint，采用最小规则集（`.swiftlint.yml`，仅启用当前代码已通过的规则），并新增 SwiftLint CI 工作流，在每个指向 `main` 的 PR 上运行。
- 新增发布系统：`GestaltX/ReleaseNotes.swift`（版本解析/校验与 Markdown 渲染）、`scripts/prepare-release.py`（校验并可选提升 Xcode 工程中的版本号、根据 PR 列表生成发布说明、验证 IPA 并记录其 SHA-256），以及仅可手动触发的 Prepare Draft Release 工作流（构建 IPA 并创建 DRAFT GitHub Release，绝不自动发布，标签已存在时大声失败）。

## [1.0.7] - 2026-11-13 - LilaShift 2.0

构建号 `11130112`。完整源码的 LilaShift 2.0 项目（本仓库），基于上游 GestaltX v1.0.7 加 PR #126。

### 新增

- 新增「国行一键解锁」，为兼容的国行 eSIM 机型一次配置：eSIM 缓存标记、美国地区代码（`LL`，销售地区不动）与 6 项 Apple 智能预设（Apple 智能、音频智能、个人翻译、照片消除、手写合成、常听 Hey Siri），共 9 项暂存更改，查看后统一应用。若无法验证 eSIM 缓存布局，整组暂存会停止并显示原因；地区代码与 AI 仍可通过各自预设单独设置。一键还原可将 9 项恢复为已记录的原值。
- 重新设计工具首页、预设分组页与更改确认页为 Liquid Glass 风格：新增共用玻璃组件（`GlassBackground`、`GlassCard`、玻璃按钮样式、`GlassFeatureRow`、`GlassCategoryTile`、`GlassStatusBadge`、`GlassBottomBar`），基于 iOS 26 原生 `glassEffect` / `GlassEffectContainer`，带 Material 回退，支持降低透明度、减少动态效果、大字号与深浅模式；国行一键解锁状态卡实时显示 eSIM、地区代码与 Apple 智能状态；预设按分组展示，每项显示状态与待应用更改数量；更改确认页汇总国行一键解锁项目的前后对比值与技术详情。底部标签栏仍使用 iOS 26 原生玻璃标签栏。
- 将 Liquid Glass 主题改为浅紫色（页面背景 #F6F3FF、玻璃 #EAE1FF、主紫 #8652DC）：浅紫玻璃解锁卡与分类卡片、紫色渐变主按钮、浅紫玻璃标签栏；深色模式保持可读的深紫玻璃主题。新增作者徽章、由真实读取状态驱动的读取进度卡（不定式——上游读取路径不输出数字进度，因此不编造百分比）与应用进度卡（备份 → 写入 → 校验 → 完成，由会话日志中的真实写入流程驱动）。
- 「关于」页新增「开源与鸣谢」区域：原项目 GestaltX（作者 huamidev）、增强版维护者 @steam8871、GNU GPL v3.0 许可证与原项目地址，并提供应用内许可证文本与源码链接；原项目其他贡献者鸣谢保持不变。
- 借鉴 Erosion-CN 加固写入路径（未照抄代码）：原地写入（`F_FULLFSYNC`、完整写回校验、失败原地回滚）、运行时动态解析 eSIM 缓存布局、应用前 Diff 预览、双金库备份（卸载重装后还在的出厂金库）、地区二选一（只改地区码，或完整美国 `LL` + `LL/A`）、四要素 Apple 智能体检与槽位级冲突防呆。
- 应用更名为 LilaShift（中文：紫序），猫照片做应用图标。

### 变更

- 保留 1.0.7 的 iOS 27.3 容器发现修复与诊断日志，包括「分享日志」入口。

### 修复

- 修复 iOS 27.3 无法定位设备容器的问题，壁纸与「App 启动图」恢复可用。

## [1.0.6] - 2026-11-12

构建号 `11122300`。

### 新增

- 新增「系统设置」，支持自定义锁屏底部文字，即时生效，无需重启设备。
- 新增「壁纸设置」，支持导入、添加和移除壁纸包，可通过分享扩展导入 `.tendies`、`.zip` 文件。
- 新增「应用启动图」，支持自选照片、将当前启动图以原尺寸保存到相册、自动备份和还原。
- 新增日语，基于 [@kagithu](https://github.com/kagithu) 提供的翻译补齐缺失文案（[#124](https://github.com/huamidev/GestaltX/issues/124)）。
- 补充 iPhone Air 灵动岛布局（[#105](https://github.com/huamidev/GestaltX/pull/105)）。

### 调整

- 为「放弃更改」补充图标；没有待处理更改时，「应用更改」和「放弃更改」统一置灰。

### 修复

- 保留设备原有的端侧 Siri 能力值，避免统一覆盖后导致 Apple Intelligence Siri 退回旧版界面（[#102](https://github.com/huamidev/GestaltX/pull/102)、[#98](https://github.com/huamidev/GestaltX/issues/98)）。
- 完善分享导入的取消处理与临时文件清理。

**完整变更**：[v1.0.5...v1.0.6](https://github.com/huamidev/GestaltX/compare/v1.0.5...v1.0.6)

## [1.0.5] - 2026-11-11

构建号 `11111140`。

### 新增

- 新增西班牙语，应用现支持 9 种语言与地区设置（[#97](https://github.com/huamidev/GestaltX/pull/97)）。
- 新增 iPhone Air 机型预设（[#92](https://github.com/huamidev/GestaltX/pull/92)）和日文 README（[#83](https://github.com/huamidev/GestaltX/pull/83)）。

### 调整

- 关于页面的支持系统改为 iOS / iPadOS 27.x。仍可在 26.x 上安装，
  但会提示不支持本机 MobileGestalt 访问。
- 更新韩语翻译（[#84](https://github.com/huamidev/GestaltX/pull/84)），修复繁体中文等语言中混入其他语言的问题（[#61](https://github.com/huamidev/GestaltX/pull/61)）。
- 中文的 Photos Clean Up 预设统一改为“照片消除”。
- 修正 Internal Build 名称，开启该系统全局标记前增加确认（[#60](https://github.com/huamidev/GestaltX/pull/60)）。

### 修复

- 访问设备时保留 App Group 原有缓存，避免影响共享同一组的其他应用（[#55](https://github.com/huamidev/GestaltX/pull/55)）。
- 还原灵动岛时同时恢复布局和功能标记，并保留其他已暂存的外观修改（[#58](https://github.com/huamidev/GestaltX/pull/58)）。
- 恢复原值时校验系统缓存代次和布局，区分无法取得的原值与原本不存在的字段，
  避免反复读取旧备份历史（[#65](https://github.com/huamidev/GestaltX/pull/65)、[#66](https://github.com/huamidev/GestaltX/pull/66)）。
- 恢复未发生变化的备份时不再重复写入设备（[#69](https://github.com/huamidev/GestaltX/pull/69)）；备份删除失败后可重试（[#70](https://github.com/huamidev/GestaltX/pull/70)），
  本地备份替换后清除继承的设备归属状态（[#64](https://github.com/huamidev/GestaltX/pull/64)）。
- 已核验的设备备份在导出时携带本机校验凭证（[#59](https://github.com/huamidev/GestaltX/pull/59)）；
  分享完成或取消后清理临时导出文件（[#62](https://github.com/huamidev/GestaltX/pull/62)）。
- 直接打开的文件会先保存再等待导入确认（[#63](https://github.com/huamidev/GestaltX/pull/63)），文件协调读取移至后台（[#75](https://github.com/huamidev/GestaltX/pull/75)）。
  临时访问失败（[#74](https://github.com/huamidev/GestaltX/pull/74)）或单个 App Group 无法访问（[#71](https://github.com/huamidev/GestaltX/pull/71)）时，不再阻塞其他排队文件。
- 加强共享导入的容器边界和符号链接检查，限制文件名元数据大小，
  清理遗留文件时避开正在写入的内容（[#72](https://github.com/huamidev/GestaltX/pull/72)、[#73](https://github.com/huamidev/GestaltX/pull/73)、[#76](https://github.com/huamidev/GestaltX/pull/76)）。
- 写入系统前拒绝设备身份字段变更（[#67](https://github.com/huamidev/GestaltX/pull/67)），校验重复的缓存描述项（[#56](https://github.com/huamidev/GestaltX/pull/56)），
  修复未修改的 NaN 值被误判为发生变化的问题（[#68](https://github.com/huamidev/GestaltX/pull/68)）。

### 下载与签名

- 部分用户反馈，iOS 27 上使用 Safari 下载的文件可能不完整。
  如果提示 IPA 损坏或无法解压，可重新下载几次；仍有问题时换用其他浏览器。
  目前尚未确认是否由 Safari 或 iOS 本身导致。
- 重签所用证书与描述文件须包含至少一个可用 App Group。
  请保留分享扩展，并为主应用和扩展配置同一个 App Group。

**完整变更**：[v1.0.4...v1.0.5](https://github.com/huamidev/GestaltX/compare/v1.0.4...v1.0.5)

## [1.0.4] - 2026-11-10

构建号 `11101436`。

### 新增

- **设备 → 预设**新增 WAPI 预设：可关闭 WAPI 监管标志，或恢复已记录的原值。
  缓存中的布尔值从设备自身的 MobileGestalt 镜像解析，而不是硬编码槽位（#30）。
- 为 WAPI 标志记录每台设备的原值。该值在编辑、App 重启、日志迁移后仍然保留，
  并与其他缓存选项一起恢复（#30）。
- 新增显示预设：高亮度始终显示、AOD 翻页组件及其条目数量、HDR 照片显示、
  壁纸视差控制，以及实验性的 PWM 和 DisplayPort 能力标记。
- 新增设备预设：车祸检测 SOS、音频混音、FaceTime 空间音频。
- 新增智能预设：端侧 Siri、音频智能、个人翻译、照片 Clean Up、手写合成、
  常听 Hey Siri。这些仍然只是能力标记，实际是否运行仍取决于硬件和地区。
- 新增韩语本地化，应用现支持 8 种语言（#24）。
- CI 现在会自动构建 ad-hoc 签名 IPA 并上传为 artifact；
  tag 和 Release 运行还会附加到对应 Release。

### 变更

- 附加选项和 WAPI 行现在直接显示在 **设备 → 预设** 中。
  已移除 About 版本号上的 10 连点隐藏解锁。
- 当前文档存在暂存修改时，打开和恢复操作会被禁用。请先保存或放弃修改，
  避免静默丢失更改（#37）。
- 版本号更新为 1.0.4（`CURRENT_PROJECT_VERSION` 11101436）。
  README 版本徽章和构建日期已同步更新。
- 所有新增的用户可见字符串均已本地化为 8 种语言
  （英语、简体中文、繁体中文（台湾）、繁体中文（香港）、越南语、俄语、
  波斯语、韩语）（#30、#38）。

### 修复

- 设备访问现在会在所有已签名的 App Group 之间回退，而不是只信任第一个。
  修复了使用包含多个 App Group 的证书签名时出现的
  `MobileGestalt access was denied` 错误（#47）。
- 字段编辑会保留完整的 64 位整数，包括大于 `Int64.max` 的无符号值。
  回读比较不再把 `UInt64.max` 与 `-1` 混为一谈（#31）。
- 打开字段但不修改直接应用时，不再重新解析显示文本，从而保留亚毫秒级
  `Date` 精度，以及数组和字典中的嵌套值（#34）。
- 应用机型名称或灵动岛布局预设时，畸形的 `ArtworkTraits` 值不再被替换或丢失。
  UI 会提示需要先在 MG Control 中修复该字段（#38）。
- 设备备份恢复会在任何写入前拒绝不同的 `CacheUUID`、`CacheVersion` 或
  `CacheData` 长度，不再恢复不兼容的缓存布局（#32）。
- 保存的备份在复用前会校验记录的大小和 SHA-256 摘要。
  没有摘要的旧备份仍然可以读取（#33）。
- 共享 plist 导入会拒绝 FIFO、socket、目录和符号链接，不再阻塞在特殊文件上，
  同时仍然接受普通文件（#35）。
- File Provider 导入会协调读取，占位文件会被物化，并发修改不会破坏读取结果
  （#39）。
- 取消分享扩展时会恢复卡住的 provider continuation，并取消底层 `Progress`，
  不再让扩展挂起（#36）。
- 拒绝或确认一个共享 plist 后，后续排队导入不再等待下一次前台事件。
  无效条目会被跳过，队列按顺序继续（#40）。
- 备份恢复会在创建恢复备份或日志记录前校验保存的布局，
  被拒绝的恢复不会产生副作用（#32）。

### 安全

- 备份完整性使用持久化的 SHA-256 摘要。同尺寸替换为另一个有效 plist 会被检测到
  （#33）。
- 收件箱扫描和导入使用 `O_NOFOLLOW` 打开文件，并要求是普通文件描述符，
  防止命名管道和符号链接攻击（#35）。

**完整变更**：[v1.0.3...v1.0.4](https://github.com/huamidev/GestaltX/compare/v1.0.3...v1.0.4)

[1.0.6]: https://github.com/huamidev/GestaltX/releases/tag/v1.0.6
[1.0.5]: https://github.com/huamidev/GestaltX/releases/tag/v1.0.5
[1.0.4]: https://github.com/huamidev/GestaltX/releases/tag/v1.0.4
