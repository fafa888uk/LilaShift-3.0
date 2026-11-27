# 紫序 4.3 开源功能集成续接记录

日期：2026-11-27（Asia/Shanghai）。

## 第二次中断后的最新状态（2026-11-27）

执行环境短暂恢复后已继续完成集成收尾，随后再次被标记为 `unavailable`。命令执行明确返回“No usable execution environment is available”；运行中的工具执行状态也被重置。以下记录以再次中断后的实际核验为准。

### 已远端保存的源码

- 本次恢复检查点包含 **`Native/DeviceConsole` 全部 195 个文件**，包括桥接层、固定版本 Rust/vendor 源码、Cargo.lock、许可证和构建脚本。远端 Native 子树为 `c5205192b44f3008bc12ab0c3e5c9f08c4f510a9`；递归读取确认 195 个 blob 且未截断。
- 这些文件仅保存在 `feature/lilashift-4.3-open-source` 的恢复提交中。应用工程仍是原来 4.2.1 的接线，**该提交不是完整 4.3 集成**。
- 主线仍为 `892947a2b1a1a44f1756b430f82232272bed04e5`，没有合并本轮新功能，没有新建 4.3 PR，也没有 4.3 IPA。
- 2,072,151 字节的 `GestaltX/Licenses/DeviceConsole-Dependencies.txt` 上传被中断。预期 blob `8f0db8ee8f692e1436c8cc68f223148faa71ca81` 再次读取为 404，**不能算已上传**。

### 已完成但尚未完整上传的工作区改动

工作区仍以 `/workspace/scratch/7fec03e58a3a/LilaShift-3.0` 为准，不能用较旧目录覆盖。下列状态来自中断前完成的文件修改与检查：

1. 独立诊断工具、个性化分组可在未读取 MobileGestalt 时进入；设备修改控件保留文档与忙碌守卫。
2. Camlo 双图工坊已接入“工具 → 个性化 → 变身壁纸工坊”，导航、About 许可、功能目录和测试目标已注册。目录为 **46 个预设 + 21 个工具页面 = 67 项**；此前漏注册的 ToolGroupMappingTests 也已补入。
3. AppleFlow 62 键、Camlo 26 键、AppleLens 28 键以及 10 个收尾词条均已合并。完整目录为 **1,989 键 × 10 语言**，包含简体中文和两套繁体中文。中文报告、局域网浏览器页面及报错正文已补齐。
4. LAN 网页本地化值使用 JSON 编码，并转义小于号、大于号、&、U+2028/U+2029，经 textContent 写入；不使用 innerHTML。HTTP 头、状态原因词与校验没有改动。
5. 三语 README、双语 CHANGELOG、RELEASE_4_3_0、FEATURE_ORIGIN_MATRIX、OPEN_SOURCE_REFERENCES、两份字节相同 Notices 已更新。来源清单为 **23 项来源、12 份许可文本**，Camlo 八个种子 plist 已与固定上游逐字节核对。
6. 最后一次源码/Xcode 配置审阅未发现明确的新增编译阻塞；**Linux 代码审阅和语法解析不能证明 Xcode 编译通过**。

### 最新实际检查

- LocalizationTests.py：4/4 通过。
- ThirdPartyNoticesTests.py：14/14 通过。
- scripts/check-licenses.py：通过，23 项来源、12 份许可文本、0 警告。
- LAN 实际嵌入 JavaScript：10 语言及脚本结束标签/恶意文件名输入检查通过。
- 局部 Swift 语法解析与 git diff --check 通过。
- 早前 Rust 的 9 项测试、device feature 检查、AppleFlow 实际 JavaScript 回归结果仍见下文。
- **尚未在最终冻结源码上跑完整 Python 套件；未跑 Xcode 编译、XCTest、最终 SwiftLint 或 IPA 构建；未做真机验收。**

### 下次恢复后的准确起点

1. 先检查上述当前工作区是否仍在，保留所有未提交文件。获取最新远端分支；本地 HEAD 在中断时仍为 `9af1c1f`，需以不丢弃工作区内容的方式与新的恢复提交对齐，禁止 hard reset/clean 覆盖未提交成果。
2. 远端已保存的 Native 文件可直接复用。磁盘 `remote-upload43-state.json` 的旧 parent/tree 仅是上传过程状态，必须以新的分支 HEAD/tree 为准；按实际 blob hash 判断是否需要重传。
3. 对最终冻结源码运行完整 Python 一致性测试、许可证检查、本地化再生成一致性和 diff 检查。
4. 上传剩余文件，远端树必须与本地暂存树一致；创建完整 4.3 提交后，再建立 PR 触发既有免费 CI。
5. 按下文执行真实编译、XCTest、快照审阅和 IPA 构建。只有成功产生与最终源码提交对应的产物后，才能报告 4.3 可下载。

---

## 以下为第一次中断时的历史快照

其中“尚未接入”“尚未合并翻译”和待办条目只描述第一次中断时的情况；最新状态以上节为准。

## 第一次中断时实际状态

用户要求把别人已发布或更新、紫序尚未接入的相关开源功能加入现有项目，继续优先使用免费 GitHub 构建。此前已授权修改代码并提交。

**这份文件是续接记录，不是 4.3 已交付的声明。** 执行环境在本次上传源码期间变为 unavailable，命令执行返回“No usable execution environment is available”，正在运行的工具状态也被重置。随后重新核实：

- 主线基线为 `892947a2b1a1a44f1756b430f82232272bed04e5`，LilaShift 4.2.1。
- 写入本记录前，`feature/lilashift-4.3-open-source` 仍指向该基线。
- 该 4.3 分支没有 GitHub Actions 运行。
- 新增实现存在于执行环境中的未提交工作区，**尚未形成完整的远端源码提交、PR、合并或 IPA**。
- 先前尝试的独立 Git blob/tree 上传可能产生未被提交引用的对象，不能把这些对象当成已保存的代码版本。不要据此宣称提交或构建成功。

## 恢复入口

当前未提交工作区：

`/workspace/scratch/7fec03e58a3a/LilaShift-3.0`

基线和本地分支：`892947a` / `feature/lilashift-4.3-open-source`。

本轮先从旧工作区 `/workspace/scratch/4817a0907f80/LilaShift` 恢复了 271 个新增/修改文件，再完成独立审查和下表中的扩展。旧工作区只有较早的一批 4.3 工作，**不包含本轮所有修复与新模块**，不得拿旧副本覆盖当前副本。

如果当前工作区仍可访问，先查看 git status、diff 和新文件，不要重新克隆覆盖它。随后获取远端最新分支，再以保留这份续接记录的方式整理提交。不可假设本地 HEAD 与远端 HEAD 仍相同。

## 已准备的集成范围

| 来源 | 固定提交 | 已写入本地代码的功能 |
|---|---|---|
| [Erosion-CN](https://github.com/Kianuni/Erosion-CN/tree/094df45ddaedb044385ada4a4bf0f22e6a6252cb) | `094df45ddaedb044385ada4a4bf0f22e6a6252cb` | 同 Wi-Fi 网页互传；26 组应用 / 65 路径 / 87 SDK 名称 / 15 配置名称的广告缓存只读检查 |
| [WQGuard](https://github.com/Kianuni/WQGuard/tree/307cf19f37864fa45bd1216bcd2ac908e92a9435) | `307cf19f37864fa45bd1216bcd2ac908e92a9435` | 固定 WQGuardCore，检查选定 IPA/TIPA 的 ZIP、Mach-O、权限声明、链接库与解析覆盖范围 |
| [GestaltX](https://github.com/huami1314/GestaltX/tree/311f78999d9f5f062f7e3b4c6374684782be5382) | `311f78999d9f5f062f7e3b4c6374684782be5382` | 设备配对、连接、主动通知声音路径捕获，接回现有声音备份/替换流程 |
| [AirCard-iOS](https://github.com/Mak5er/AirCard-iOS) / [idevice](https://github.com/jkcoxson/idevice/tree/7bd551c16c6dd2e058740d85a2d9399a51a776e9) | GestaltX 固定的连接层；idevice `7bd551c16c6dd2e058740d85a2d9399a51a776e9` | 原生 RSD/Lockdown、配对及 syslog 连接代码；不含 Airlift 文件注入或 Wallet 修改 |
| [AppleFlow](https://github.com/Kianuni/AppleFlow/tree/7086c9584367e56c545099e76f951291a04c885b) | `7086c9584367e56c545099e76f951291a04c885b` | 七格式配置生成与离线配置体检；内置 JS 在 JavaScriptCore 中运行 |
| [AppleLens](https://github.com/Kianuni/AppleLens/tree/3e4919433ebaaa0797544603ef9e1da4ba961b4c) | `3e4919433ebaaa0797544603ef9e1da4ba961b4c` | 用户导入/粘贴 AI/Siri 文本日志，按八类信号汇总；导出不含原始日志正文 |
| [Camlo](https://github.com/Kianuni/Camlo/tree/be573b398da45b3834cb11104748ce742e826c38) | `be573b398da45b3834cb11104748ce742e826c38` | 双图动态壁纸工坊、渐变/揭幕预览、真实 .tendies 生成与现有壁纸存储导入 |

这是各来源的选定模块集成，**不代表移植上述整个应用**，也不代表发现了互联网上全部开源项目。

### 重要功能边界

- 广告缓存模块目前是检查与报告，未移植清空目录、改写配置或 chmod 锁定。不得称为已实现全局去广告。
- Wi-Fi 只共享专用收件箱；每文件 256 MiB、收件箱 1 GiB、200 文件；HTTP，无公网传输承诺。
- IPA 输入 256 MiB、总展开 512 MiB；静态检查不等于签名验证或安全认证。
- 配对/捕获由用户开始，五分钟上限；持久化只保留应用标识和声音文件名，不保留通知正文/完整日志。LocalDevVPN 为外部配套应用。
- AppleFlow 支持 Surge、Loon、Shadowrocket、Stash、Mihomo、Quantumult X、sing-box 导出；sing-box JSON 不在本地审查支持范围。配置体检为静态规则检查。
- AppleLens 只分析文本日志信号，错误码不能证明故障根因；进度只能来自日志中的实际百分比/字节比例。输入 2 MiB、20,000 行，超过 8 KiB 的单行跳过并计数。
- Camlo 本轮只接入双图工坊。没有接入视频/Live Photo、3D 抠图、粒子、云图库、全套私有预览或新设备写入路径。系统应用仍需经过紫序原来的兼容性和备份流程。

## 文件与集成入口

已恢复的主要模块包括：

- `GestaltX/LANTransfer*.swift`
- `GestaltX/IPAInspection*.swift`
- `GestaltX/AdCache*.swift`
- 配对、设备连接、通知捕获与 `Native/DeviceConsole`
- `docs/RELEASE_4_3_0.md`、对应本地化、Xcode 工程及工作流改动

本轮新增：

- `AppleFlowEngine.swift`、`AppleFlowJavaScript.swift`、`AppleFlowView.swift`
- `AppleLensLogInspector.swift`、`AppleLensLogView.swift`
- `MorphWallpaperWorkshop.swift`、`MorphWallpaperWorkshopView.swift`
- `GestaltX/Resources/CamloPosterSeed.bundle`，8 个上游 plist 模板
- `tests/AppleFlowTests.swift`、`tests/AppleLensLogTests.swift`、`tests/MorphWallpaperWorkshopTests.swift`

入口签名：

```swift
AppleFlowView(share: share)
AppleLensLogView(share: share)
MorphWallpaperWorkshopView(customizations: customizations)
```

当前工作区已经完成 AppleFlow / AppleLens 的工具页导航、FeatureCatalog、About 与测试目标注册。**Camlo 导航、FeatureCatalog、About、测试文件注册尚未接入。**

应用 GestaltX 目录使用 PBXFileSystemSynchronizedRootGroup，Swift/资源自动加入；tests 使用显式引用，需要单独注册。

## 已完成的具体修复与验证

### 审查修复

- 长文件名重复上传后仍保持 UTF-8 长度限制，可列表、下载和移除。
- IPA 文件选择回调同步取得安全作用域，取消后抑制迟到报告。
- 关闭捕获页面后不再由迟到 VPN 检查启动捕获。
- 取消配对后丢弃旧回调、PIN 通知与旧后台任务回调。
- 捕获结果按顺序有限批次持久化，最多 2,048 个去重结果。
- 重新配对清理旧凭据，忘记配对清理孤立凭据，拒绝符号链接目录。
- 原生 syslog 读取错误会返回失败。
- AppleLens 文件读取采用 no-follow / nonblocking、描述符类型核验和有界读取；修正负数进度、错误码前缀误匹配、末尾换行计数。
- AppleFlow 修正恰好 2,500 行且末尾有换行的边界。

### 实际已经运行

- 恢复早期 4.3 后，39 项 Python 一致性测试和许可证检查通过。后续加入 AppleFlow/Lens/Camlo 后必须重新运行，旧结果不可复用。
- Rust `cargo test --locked --offline`：9/9 通过。
- Rust `cargo check --locked --offline --features device`：通过，5 条既有 idevice-ffi 警告。
- 实际 AppleFlow 嵌入 JS：7 组上游审查/隐私回归、七格式生成、Loon PROXY 占位、注释误判检查通过。
- 各新增/修改模块进行了 tree-sitter 语法检查；Camlo 八个 plist 解析通过。
- **未运行本次 Swift 类型检查、XCTest、iOS 模拟器或 IPA 构建。语法检查不能替代这些步骤。**
- 未进行真机安装、配对、通知、Wi-Fi、动态锁屏或原有 eSIM/AI/恢复验收。

## 恢复执行环境后必须完成

1. **修复工具入口。** `ContentView.swift` 中 standalone advancedDiagnostics NavigationLink 仍有 `.disabled(!model.hasDocument || model.isBusy)`；`ToolGroup.requiresDocument` 也需要一致处理。独立文件工具应可在首次打开或 iOS 26 未读取 MobileGestalt 时打开，设备修改控件保持原来的文档/忙碌守卫。
2. 接入 Camlo 导航、目录、About/许可证和 `MorphWallpaperWorkshopTests.swift`。工坊适合个性化/壁纸入口，不自动应用系统。
3. 合并剩余翻译。中间文件均为 `{key: {locale: translation}}`：
   - `/workspace/scratch/7fec03e58a3a/applelens-translations.json`：28 键 × 9 语种；**已写入生成器和 locale JSON，尚未完成最终全量生成/验证**。
   - `/workspace/scratch/7fec03e58a3a/appleflow-translations.json`：62 键 × 9 语种，包含 23 个动态标题键；**尚未合并**。
   - `/workspace/scratch/7fec03e58a3a/camlo-localization.json`：26 键 × 9 语种，包含两个动态图片按钮键；**尚未合并**。
4. 当前 FeatureCatalog 期望已调整为 46 预设 + 20 页面 = 66，添加 Camlo 后还要更新相应计数/类别及导航测试，保持测试覆盖。
5. 补齐 AppleFlow / AppleLens / Camlo 的 README 三语、CHANGELOG、4.3 集成记录、FEATURE_ORIGIN_MATRIX、OPEN_SOURCE_REFERENCES、THIRD_PARTY_NOTICES 和应用内相同 Notices。检查脚本当前仍按 20 项来源；新增 3 项后应为 23 项。AppleFlow-MIT 文件已存在；AppleLens license 的复制需核实是否完成，Camlo GPL 模板与代码需如实署名。
6. 完整检查：本地化生成、39 项 Python 一致性套件、许可证、diff；然后提交全部源码，建立 4.3 PR 触发免费的现有 CI。工作流 push 过滤尚不含 4.3 分支，PR 到 main 才会触发相应检查。
7. 在同一提交上运行 SwiftLint、XCTest、IPA。修复真实编译/测试失败，不降低测试门槛。
8. 4.2.1 → 4.3.0 的标题预计会影响四张首页快照：unread、populated、narrow-320、accessibility。保留旧参考，下载 snapshot-failures 的实际新图，逐张审核后只替换合理差异，再跑完整套件。不得使用 blanket record、跳过测试或降低精度。
9. 全部检查通过后按用户授权整合，并提供与源码 SHA 对应的 IPA、SHA-256、manifest 和真实 CI 链接。不得把草稿/分支/源码就绪当作已发布或真机验证。

## 已核对但未新增独立模块的上游

- [Erosion f6450a147](https://github.com/jailbreakdotparty/Erosion/commit/f6450a147cb42e7f4d13f187fd13496b493f5c30)：近期改动集中在文件浏览缓存、容器查找和信息页整理，与已有模块重合，未按提交数虚增功能。
- [WQFiles d4aae98](https://github.com/kolbicz/WQFiles/tree/d4aae98ca01d416ea23c60a9fe5c074b5b810798)：近期主要安装说明，容器枚举已是既有参考。
- [WCMigrate 55faba721](https://github.com/yangokok886/WCMigrate/tree/55faba721fd44e04c65be481860c9d93e12f6f61)：第三方应用数据移动/替换/合并与当前自有数据存档不同，缺少整任务回滚，未接到现有备份按钮。
- AppleLens 的 macOS USB/进程雷达不适用于这个 iOS IPA；Camlo 的完整视频/3D/云图库不在当前双图工坊范围。以上不得标为已全部移植。
