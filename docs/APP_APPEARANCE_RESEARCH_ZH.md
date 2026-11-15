# LilaShift 2.0 — 应用桌面图标与名称研究 / App Appearance Research

状态：**研究原型**（2026-11-14）。维护者：@steam8871；基于 GestaltX by huamidev（GPL-3.0）。
**严禁将预览称为真正修改已安装微信。** 本分支不修改微信 Bundle、签名、聊天数据、SpringBoard、LaunchServices 或系统图标缓存。

## 已实现
- 在现有「启动图」详情页增加隔离的「App Icon & Name · Preview Only」分区（`AppAppearancePreviewView`，独立文件 `GestaltX/AppAppearanceViews.swift`；启动图编辑器本身不再承载预览状态）。
- 从相册导入图片并预览自定义图标，输入并预览自定义桌面名称；预览不持久化到目标 App，也不执行系统写入。
- 图片校验（`AppAppearanceValidatedImage`）：按 magic bytes 识别 PNG / JPEG / HEIC，拒绝空文件、超过 5 MB 的文件、不支持的格式、无法解码的文件、任一边超过 4096 px 的图片；每次失败都给出具体原因，不静默丢弃。
- 预览图用 ImageIO 下采样后裁剪（最长边不超过 512 px），不把原图全分辨率解码进内存；HEIC 按原始字节导入，不经过 `.compatible` 转码。
- 自定义裁剪（`AppAppearanceCrop`）：全图 / 居中正方形 / 自定义边距（0–40%），裁剪矩形按真实像素尺寸计算并钳制；圆角预览滑块 0–27。
- 撤销（`AppAppearancePreviewHistory`）：每次离散修改入栈，连续输入（打字、拖滑块）不淹没历史；拖动滑块松手后才作为一次可撤销操作提交。
- 本地草稿（`AppAppearanceDraft`）：只保存在紫序自己的 Application Support 目录（`GestaltX/AppAppearance/Drafts/<bundleID>.plist`），PropertyList 原子写 + 回读校验；文件内含图片 SHA-256，篡改、改名冒用、损坏文件均被拒绝。
- `AppAppearanceProposal` 严格验证 Bundle ID 与名称（空白、超长、控制字符），`canApplyNatively` 固定为 false，新增 `capability` 固定为 `.unknown`（默认未知，永不默认可写）。
- 新增 XCTest：格式识别、校验五种失败、裁剪矩形、裁剪缩略图尺寸、撤销历史、草稿保存/读取/篡改拒绝、名称边界、能力默认未知；并修复了原测试中 `"WX\\nBad"` 的错误断言（字面反斜杠不是控制字符，应为真实换行）。
- 所有新增界面文案均走 `L()` 本地化（10 语种同步）。以上均须由真实 CI 编译、测试、真机 UI 检查后才能宣称通过。

## 已验证的不同技术路径
1. **启动快照**：已有 `LaunchArtworkFiles.swift` 访问 app 数据容器的 `Library/SplashBoard/Snapshots/<bundle> - {DEFAULT GROUP}`。这是启动过程中短暂出现的图片，不是主屏幕图标。
2. **主屏幕图标**：由 SpringBoard / IconServices 等管理，可能引用应用图标资源和系统缓存。缓存地址、权限、重建和系统版本均须真实验证；不要从 SplashBoard 可写推论其他缓存可写。
3. **名称**：可能来自 Bundle 的 `CFBundleDisplayName`、本地化资源以及 LaunchServices 的显示名数据库。已有 `GXLaunchServicesDatabase.m` 实现只读发现；不可把读取能力当成修改权限。
4. **越狱 Hook**：能够在具有代码注入权的越狱环境改变 SpringBoard 的图标渲染/名称返回值，但普通 iOS 27 不能自动获得该权限。
5. **官方 Alternate Icons**：应用自身才能调用 `setAlternateIconName`，不是对第三方 App 的通用修改 API。
6. **快捷方式**：可替代桌面入口的视觉效果，但不等同原生图标，不保证原生角标；只能明确标成替代方案。
7. **重签 IPA**：修改应用自身签名资源意味着身份/数据/权限变化。禁止以微信主号或已有用户数据作为实验对象。

## 开源项目研究矩阵（版本和许可按引入时重新核验）
| 项目 | 地址 | 当前仓库许可（核验时间 2026-11-14） | 研究用途 | 代码策略 |
| --- | --- | --- | --- | --- |
| GestaltX | https://github.com/huamidev/GestaltX | GPL-3.0 | 项目上游、MobileGestalt、备份 | 遵守版权与 GPL |
| Erosion-CN | https://github.com/Kianuni/Erosion-CN | GPL-3.0 | 安全写入、动态布局、诊断 | 审阅后独立合入 |
| MGKeys | https://github.com/PoomSmart/MGKeys | MIT | MobileGestalt 键名解码和映射 | 保留 MIT notices |
| WQFiles | https://github.com/kolbicz/WQFiles | GPL-3.0 | 系统文件发现/路径权限的研究 | 仅在证据确凿时使用 |
| LumenBoard | https://github.com/xsxs18-dev/LumenBoard | MIT | 越狱环境图标渲染思路 | 不承诺非越狱可用 |
| Rune | https://github.com/KrisButIAmAnOSDev/rune | MIT | SpringBoard Hook 对照 | 仅用于隔离实验环境 |
| WorkPlot | https://github.com/gievano/WorkPlot | GPL-3.0 | 预设与操作会话交互 | 以真实版本适配为限 |
| Gester | https://github.com/sasobhabha/Gester | MIT | 诊断与设备访问设计 | 隔离权限行为 |
| idevice | https://github.com/jkcoxson/idevice | MIT | 桌面端设备通信 | 后续独立模块 |
| pymobiledevice3 | https://github.com/doronz88/pymobiledevice3 | GPL-3.0 | 辅助诊断与测试工具 | 外部测试工具优先 |
| Nugget | https://github.com/leminlimez/Nugget | AGPL-3.0 | 只做设计/历史研究 | 不复制代码 |
| swift-snapshot-testing | https://github.com/pointfreeco/swift-snapshot-testing | MIT | SwiftUI 页面截图回归 | 可引入测试目标 |
| SwiftLint | https://github.com/realm/SwiftLint | MIT | 静态质量和复杂度 | 可引入 CI |

**许可证警示**：每个仓库须检查具体 commit、子目录和 vendored 代码的许可证，AGPL 不应未经合规审查混入 GPL 分发。图标/品牌资源另行核查商标和版权。

## 后续阶段与验收
- **Gate 0**：首先把原有 PR #2 的 ModifiedValues CI 修绿；比较修复提交与完整错误日志，严禁删测、静默跳过。
- **Gate 1**：保留本分支仅预览，不向用户显示假状态。新增静态架构报告：所有推断标明“推断”，缓存偏移未知写“未知”。完成 XCTest + IPA build + UI 真实验收。
- **Gate 2**：开发注入式 `AppAppearanceBackend` 协议：`inspect(bundleID)` 返回 `unavailable/unknown/readOnly/verifiedWritable` 与证据元数据，默认 unknown。具体系统路径只能由真实设备只读检测得出，硬编码与猜测一律禁止。
- **Gate 3**：研究读取（不写入）图标缓存及名称来源，设备、系统 build、inode、路径、权限和摘要必须可复核；任何读取失败不回退猜测。
- **Gate 4**：仅在合法、经用户许可的隔离测试设备上试验受控写入。强制来源可信的完整备份，原文件哈希/布局匹配，失败恢复和重启后重新读取；不可碰微信账号数据或系统关键路径，异常停机。
- **Gate 5**：在不同 iOS 27 build、国行和非国行、重启、应用更新及设备数据迁移下验证。无充分真实证据时不可称支持「原生微信图标/名称替换」。
- **Gate 6**：整合智能兼容性、设备识别、原生 AI 过滤、SafePatch diff、可信恢复时间线、预设数据库、故障诊断，并保持各模块隔离与 fail-closed。
- **Gate 7**：若上游 GestaltX 新版本有可核实提交，独立分支逐步迁移，确保 Bundle ID 和 App Group 一致，扫描器保持动态解析；铃声和配对分别做真机验收。

## iPhone Air A3518 / iOS 27.0.1 取证入口

在「工具 → 操作 → 应用图标与名称」选已安装应用。列表复用设备应用清单，进入页面后查看实际 iOS Build、LaunchServices 解析出的两个名称字段、数据库字节数和 SHA-256，以及系统图标查询返回的图片。可分享纯文本摘要。系统图标查询可能返回未知；查询结果不能用来定位磁盘图标记录。现有自定义图标、名称与撤销入口仍用于预览。

写入还需要在该 Build 上定位实际读用的 IconServices 记录，确认 LaunchServices 名称记录、更新缓存的时序及恢复方式，再分别校验设备桌面与重启后的结果。

Windows 签装版会随摘要附带磁盘图标缓存探针。它以只读方式检查两个历史候选目录，在根目录和一层 UUID 子目录中统计常见记录类型，并抽样匹配所选 Bundle ID 的文件名或 UTF-8 / UTF-16LE 字节。摘要记录打开错误、扫描限制及候选记录大小和 inode。候选仍须验证是否是主屏幕实际采用的图标；零匹配也可能表示条目使用散列索引或超出抽样范围。[Filza 路径记录](https://www.tigisoftware.com/default/?page_id=177) · [Bergamota 对 .isdata 的观察](https://github.com/ry-diffusion/Bergamota/blob/develop/NOTES.md)

## 图标缓存探针 v2 与受控写入门禁（3.1，未在真机验证）

### 探针 v2 诊断（`GXIconCacheProbe`，只读）
上一轮探针无法说明唯一条目为什么不可读（fstatat、openat、fstat 校验、read、readdir 无法区分）。v2 为每个条目记录诊断，不改变扫描上限（1800 条、4 秒、24 MB 读取预算、128 KB 前缀、16 条匹配）：
- 每个条目：名称、dirent `d_type`、stat mode（八进制）、大小、uid、gid、inode；失败时记录阶段 + errno。阶段：`readdir`、`iteratorOpen`、`fstatat`、`childOpen`、`prefixOpen`、`prefixFstat`、`prefixRead`、`nonRegular`。
- 元数据枚举：即使内容读取被跳过或失败，也记录条目元数据；每根目录附 `directoryStat`（根目录 mode/uid/gid/inode）；`entriesDetail` 数组上限 32 条，`unreadableStages` 按阶段计数、`stageErrnos` 记录各阶段最近一次 errno。
- fstatat 失败时，以完整路径再试一次 `stat()` 作为第二意见并记录其 errno；符号链接（及未知类型）改用 `lstat()`，绝不跟随链接到扫描根目录之外；符号链接记录 `readlink` 目标但不跟随。FIFO 等非正规文件记录类型（如 `fifo`）而不打开。
- 匹配记录新增 `prefixSHA256`：对已匹配文件，取探针实际读取的前缀（至多 128 KB）的 SHA-256。探针不做全文件哈希——写路径的 TOCTOU 与回读校验比较的是同一前缀窗口，而不是探针从未计算过的全文件哈希。
- 检查页新增一行本地化文案，显示不可读条目的阶段 breakdown（如 `fstatat ×1 · prefixOpen ×2`）；无不可读条目时显示“没有无法读取的条目”。

### 最新真机证据与门禁状态（2026-11-16，iPhone Air iPhone18,4，iOS 27.0.1，Build 24A446）
- systemgroup 图标缓存目录（`/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.lsd.iconscache/Library/Caches/com.apple.IconsCache`）能打开（open 1，errno 0），但其唯一条目不可读、匹配 0 条、读取 0 字节，未触及扫描上限；另一候选路径（`/private/var/mobile/Library/Caches/com.apple.IconsCache`）不存在（errno 2）。系统图标 PNG 的 SHA-256 未知。LaunchServices 缓存已重建（14,696,448 字节，SHA `3b379675…`）。
- **门禁状态：未在真机验证。** 该记录未被证实是主屏幕实际使用的记录，因此写路径保持门禁。v2 探针正是为回答“唯一条目为什么不可读”而设——在 v2 给出阶段 + errno 之前，不得假定该条目可写、不得绕过门禁。

### 受控写入设计（仅代码，未在真机运行）
- `VerifiedIconCacheRecord`（bundleID、缓存根内相对路径、大小、inode、探测时前缀 SHA `sha256AtProbe`、探测时 LaunchServices 缓存 SHA `probedCacheSHA`）：只能从包含至少一条该 bundleID 匹配且带前缀哈希的探针证据构造（`fromEvidence(_:bundleID:)`，否则为 nil）。
- `IconCacheWriteGate.evaluate`：首个实现仅接受 bundleID `com.yueyou.cyreader`（七猫小说），其他一律 blocked（注释：微信/支付宝待七猫小说验证后跟进）。图标替换明确拒绝（`.blocked`，原因“图标记录格式未确认”），直至探针确认图标字节。
- `WriteMutation`：显式描述一次字节替换（偏移 + 长度 + 替换字节）。首个构造器仅支持匹配前缀内的显示名称字节替换（UTF-8 与 UTF-16LE 两种形式）：新名称须与当前名称编码后字节长度相同、且在两种形式中合计恰好出现一次，否则拒绝；图标字节永不经此构造器修改。
- `IconCacheWritePlan` 状态机：`idle -> backedUp -> written -> readBackVerified -> awaitingRestartVerification -> verifiedAfterRestart`，另有 `restored` 与 `failed(reason)`。备份在紫序自己的 Application Support 目录（`GestaltX/AppAppearance/IconCacheBackups/<bundleID>/`，PropertyList + SHA-256，沿用 `AppAppearanceDraft` 式存储），写前写后各算一次 SHA-256 并原子写入，恢复验证通过前不删除备份。写入为单条记录：证据匹配数不等于 1 即拒绝；当前前缀 SHA 与探测 SHA 不符即拒绝（TOCTOU）；无有效备份即拒绝。写入为原地同长替换（inode 与文件大小不变），回读时核对替换字节与预期写后前缀 SHA，不符立即用备份恢复并报告失败。重启复验复用仓库已有的启动证据（`BootSession.current()` + `RestartEvidence.compare`）：仅当确实重启过且新探针仍显示该替换时，才标记为 verified-effective；此前一直停留在“等待重启验证”。
- “候选记录”与“重启后验证有效”在代码名、界面文案与本文档中严格区分，绝不把候选说成有效，绝不宣称已在真机验证。
- 界面：仅七猫小说的检查页出现写入口——一行门禁状态、一个新显示名称输入框、“写入（实验性）”按钮（门禁未就绪时禁用）、一个独立的“从备份恢复”按钮（仅在写入待定/等待重启验证/失败持有备份时启用）。写入按钮执行“备份 → 写入 → 回读”后停在“等待重启验证”，不自动恢复、不提供未经重启检查的持久修改。

### 下一步真机操作（按顺序）
1. 安装含探针 v2 的构建，打开「工具 → 操作 → 应用图标与名称 → 七猫小说」，点“重新读取”，分享证据文本：`entriesDetail` 与 `unreadableStages` 会指明唯一条目的失败阶段与 errno。
2. 若阶段为 `prefixOpen`/`prefixFstat`/`prefixRead` 且 errno 为 EACCES/EPERM：该条目在当前权限下不可读，门禁继续 blocked，不得尝试写入；记录 errno 并评估是否需要其他只读发现路径。
3. 若出现匹配记录且门禁显示“已就绪——仅为候选记录”：输入与当前名称编码字节长度相同的新名称（例如同为 4 个汉字），点“写入（实验性）”，确认状态走到“等待重启验证”、回读无报错。
4. 重启 iPhone，重新打开同一检查页并点“重新读取”：状态变为“重启后验证有效”且主屏幕名称确实改变，才算验证有效；否则状态保持“等待重启验证”，用“从备份恢复”还原，并记录重启前后两次探针的 `prefixSHA256` 与 LaunchServices 缓存 SHA。
5. 在七猫小说验证有效之前，不对微信、支付宝或任何其他应用开放写入按钮。

### UI 原则
- 与现有启动图编辑器明确隔离，不把启动快照当应用图标。
- 真值状态分为：未读取、不可访问、仅预览、已验证写入、重启后验证、未知。
- 所有高风险项有中文用途、风险、设备要求、前后值、备份证据和恢复方式。
- 支持系统深/浅色、VoiceOver、动态字体、加载、空状态、失败重试、搜索和无障碍标注。

### 交付与禁止事项
- 每个模块独立分支、Draft PR；`main`、旧正式版 Release、正式签名均保持不变。
- 不自动创建系统路径的写入 exploit，不注入未越狱系统，不绕过系统权限。
- 未通过真实 CI、模拟器测试、IPA 元数据核验及真机验收的功能不得宣传已完成。
- 必须注明代码版本、commit SHA、CI 运行 URL、通过/失败/跳过计数、已知风险、是否可恢复、许可证归属和回滚流程。
