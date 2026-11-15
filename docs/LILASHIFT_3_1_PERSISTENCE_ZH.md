# LilaShift 3.1 持久化专项

## 基线包与提交

核对日期 2026-11-15（北京时间）。专项以远端 main 的 `b39656d1de625fffa15904ec21241f636ae3a2d6` 为基线。三份已有 IPA 都是 **3.0.0 (30000002)**，App 和 Share Extension 使用 iPhoneOS 27.2 SDK、Xcode 27B52。逐个解包查验 Mach-O CodeDirectory 的 ad-hoc 标志与签名内 App Group `group.com.huami.gestultx`。两份 bundle 均未嵌入 provisioning profile，安装或重签后的签名状态要在实际测试设备上记录。SDK 版本是打包信息，设备 iOS 版本和 Build 仍待采集。

| 包 | 对应源码 | IPA SHA-256 |
| --- | --- | --- |
| 公开 `v3.0.0-rc.1` | `c709ae84a697a82a2a4d51c7336e0d12d9f4d903`，tag 和构建来源 | `ce3207e5d233b6da8a958545ca77974440d98f6338bb2e3a37f514294acc9ae2` |
| 历史本地测试包 `fc022893` | `fc0228932b895dfc63029e5ac3ba4dbab2f3a425`，历史 Actions 归属 | `1d51fe73e189c2f9c4b08d5d02da7a2801bf0f416ca67ae2751703bdc2b37415` |
| 历史本地测试包 `faa9426f` | `faa9426f50a0fa862f879f9ead23362883f683b4`，历史 Actions 归属 | `51a60b8d4fbb8d4c25ad381fc3b1b58a6404ac5243edd94b7aec7ddb497d77fe` |
| 本专项 CI 测试包 | `3.1.0 (31000001)`，实际 SHA 写入两个 bundle 的 `LilaShiftGitCommit` | 从 Draft PR 对应的 Build IPA job 摘要与下载的 IPA 原件核对 |

[公开 RC 与 GitHub 资产](https://github.com/fafa920q-hue/LilaShift-2.0/releases/tag/v3.0.0-rc.1) · [公开 RC 对应源码](https://github.com/fafa920q-hue/LilaShift-2.0/tree/c709ae84a697a82a2a4d51c7336e0d12d9f4d903) · [main 的测试基线](https://github.com/fafa920q-hue/LilaShift-2.0/actions/runs/43710108428) · [历史协作包构建](https://github.com/fafa920q-hue/LilaShift-2.0/actions/runs/43611895984)

## 根因

1. `DeviceAIEligibility` 本来就列出了 `iPhone18,2`。旧流程把硬件资格、Preview 的 CacheExtra 布尔计数和主 AI 键的实时回答当作整组能力的信号。现在硬件资格保留，自动设置跳过六项，独立控件与逐键实时观察保留。
2. 原验收读取 `working`，其中可能有未提交变更、导入文档或写入回读。原候选条件只比文件值。现在已核验的写入记录单独保存，验收只吃重新连接捕获的真机数据和同期 MG 回答。使用系统启动时间、读取时序和相同 Build 判定，人工加重新读取提供较低证据等级。
3. #178 的 CacheExtra 和 CacheData 同名，层和类型独立。已有的槽位样本来自其他机型，`iPhone18,2` 的槽位基线从首读取得。动态描述符或原始值不可用时显示未知。本机型仍保留 Audio Intelligence 入口和说明，阻止自动改写目标组合或把槽位改到 1。
4. 传统 Siri 设置、设备专用 Siri capability、Apple Intelligence 界面和 Siri AI Beta 使用各自的观察。Apple Account 地区、Siri 语言及 Beta 设置来自用户查看系统设置，Beta 条件匹配和设置就绪是不同状态。账户服务端答复仍需从入口或实际使用观察。 [Apple 硬件型号](https://support.apple.com/en-us/108044) · [Apple Intelligence](https://support.apple.com/en-sg/121115) · [Siri AI 条件](https://support.apple.com/en-us/127893)

## 六项逐键报告

当前没有 A3527 真机读取。下表的目标表示历史单键配置定义或供测试的显式目标。专项一键在该机型保持当前值，本次真机原值、类型、当前文件值、当前 MG、重启后文件值及重启后 MG 均待实测。每行观察范围由本次设备 ProductType / iOS Build 显示，特性实际适用 Build 待核验。

| 项目 | 原始 MG 键 | 目标与专项处理 |
| --- | --- | --- |
| Apple Intelligence Capability | `A62OafQ85EJAiiqKn4agtg` | 历史目标 Boolean true。原生硬件保留值，主键单独查询。 |
| Audio Intelligence | `rb2tKZxlj0Gm2tBmUQSLqQ` | 专项目标保持。另读动态 CacheData 槽位，显示 #178 的实测组合和证据等级。 |
| Personal Translator | `M1n2sAqf33NAOgZRGxQYBA` | 历史目标 Boolean true。独立读取 CacheExtra、动态 CacheData 和 MG。 |
| Photos Clean Up | `XNCjqOupLM/S8fNyxRNQTA` | 历史目标 Boolean true。可用于隔离的单键测试。 |
| Handwriting Synthesis | `YgYIIViDt1kgzyIsIV61vA` | 历史目标 Boolean true。独立读取并在适用 App 验证。 |
| Always-Listening Hey Siri | `TusANsf9Lfe3P/9fIXXSrQ` | 历史目标 Boolean true。独立查询，实际唤醒用系统测试。 |

验收同时记录文件匹配和 MG 回答。文件目标值保留而 MG 无回答时仅给出文件证据。强证据、文件与实时值都符合且原值确实不同的记录才进入 `restartVerifiedCandidateIDs`。

## Siri 独立状态

| 项目 | 证据 | A3527 当前 |
| --- | --- | --- |
| 传统 Siri | 系统“Apple Intelligence 与 Siri”设置、唤醒和实际问答 | 待用户确认 |
| Siri 本机能力 | CacheExtra `K/R1GfGfCkXvEhaPS2Vrng` 的原始类型、当前值及独立 MG 回答；一键保持 | 待实测 |
| Apple Intelligence | 原生硬件资格、主 MG 键、Settings 和独立功能操作 | 硬件资格已确认；MG、Settings 和功能待实测 |
| Siri AI Beta | iOS、设备语言、Siri 语言、人工账户地区、Beta 入口及开关、等待名单、语音、模型下载 | iOS 和设备语言待真机读取；系统设置待用户确认 |

## 真机复现与验收

1. 从 Draft PR 的 Build IPA 下载测试包，验 SHA-256、版本、Build 和两个 `LilaShiftGitCommit`，记录重签方式及实际 App Group。使用 iPhone 17 Pro Max A3527，记录设置里显示的 iOS 和系统 Build。
2. 首次打开 App 使用“重新连接并读取设备”，记录 `DeviceBaseline` 和指纹。截图或抄录六键与 Siri 四项，另从设置确认真实 Apple Account 地区和 Siri 语言。此步只观察。
3. 选一个原本未配置并允许手动操作的独立键（例如适用的 Photos Clean Up），确认变更预览仅包含该键。Apply 后记录文件写入回读和指纹。尝试同一启动会话重读，验证无重启确认和无系统验收计数。
4. 真机完整关机再启动，解锁并打开 App，重新连接和读取。记录证据等级、六键原值及类型、目标、文件和实时值。用户勾选只能随一次新的真实读取提供人工级证据。
5. 对照指纹和逐键证据。文件标识改变加上字节、UUID 或布局证据支持重建，执行者仍未知。目标回到原值或第三值是覆盖证据；目标保留且实时不符是采用不一致；布局和布局解析单独列出。同名 CacheData 槽与实时回答相符可以指向候选配置层，还需设备/Build 实验证明实际来源。
6. 单独验证系统设置、传统 Siri、真实功能、Beta 入口和下载状态。对照读回结果按允许路径还原测试改动并重新读取。原生组合或 Audio Intelligence 无法验证时可保留诊断数据。

## 文件与测试

- 基线与观察：`DeviceBaseline.swift`、`DevicePersistenceDiagnostics.swift`、`GestaltDocument.swift`、`GestaltManager.swift`、`LiveGestaltProbe.swift`。
- 资格、分层和自动写入：`DeviceAIEligibility.swift`、`Capabilities.swift`、`AIReadinessCheckup.swift`、`DeviceCacheOptions.swift`、`LilaIntelligence.swift`、`LilaIntelligenceCore.swift`。
- 真机诊断、Siri UI、验收：`SiriBetaStatus.swift`、`ContentView.swift`、`PostModificationAcceptance.swift`、`PostModificationAcceptanceViews.swift`、`SmartFaultDiagnosis.swift`、`SmartFaultDiagnosisViews.swift`。
- XCTest：`StandalonePresetsTests.swift`、`PostModificationAcceptanceTests.swift`、`LilaIntelligenceTests.swift`、`SmartFaultDiagnosisTests.swift`。覆盖原生资格、无冗余写入、单键写入、按键探测、文件和系统分歧、重启回退、UUID、无实时回答、Siri 原样保留、地区/语言、重启证据和错误。
- 构建：`.github/scripts/build-ipa.sh`、`.github/workflows/build.yml`、`GestaltX.xcodeproj/project.pbxproj`。单元测试和产物校验的实际结果见 Draft PR 对应 Actions。模拟器任务验证实现和 fixtures，A3527 真机步骤单独留证。

## 未决

- A3527 用户设备的版本、Build、CacheUUID、布局、六键和同名槽读数、账户和 Siri 设置、服务端资格及功能可用性。
- #178 的原始 issue 在交付仓库 API 返回 404。同名 CacheExtra 组合的实际效果和有效配置层仍需该设备/Build 取证。
- App Group 重签环境和系统启动时间接口的真机可用性。启动时间无法取得时保留人工等级。
