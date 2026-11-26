# LilaShift 4.2.1 · 维护更新与验收记录

准备日期：2026-11-27（Asia/Shanghai）。应用版本 `4.2.1`，构建号 `42000002`，预期文件名 `LilaShift_4.2.1.ipa`。

本文随构建源码冻结，记录更新范围和验收入口。最终源码 SHA、实际 CI 结果和下载位置以本次集成 PR 与构建 manifest 为准；本文不预填运行结果，准备源码不等于已经公开发布。此前已发布版本为 [v4.2.0](https://github.com/fafa888uk/LilaShift-3.0/releases/tag/v4.2.0)，其源码提交为 `3152fc7c49ccb00f80f97da90666a65fb66a6d89`，build `42000001`。

## 本次更新

| 范围 | 实际改动 |
|---|---|
| 压缩包依赖 | ZIPFoundation 0.9.20 → 0.9.21，精确锁定版本与提交，纳入上游损坏压缩包及符号链接路径校验修复 |
| 本地化 | 补齐 4.x 界面漏入目录的多语言文本，保留安全警告与格式占位符，纳入验收检查 |
| 关于页 | HTTPS 来源链接校验，无效链接显示文字；移除未使用的状态订阅 |
| 主线与文档 | 以 4.x 为应用基线整合旧 `main` 历史及 PR #20–#25；中、英、日区分当前源码与历史发布 |
| 工作流 | 退役旧主线独有的 30 个一次性补丁工作流；普通 CI 最小只读权限，checkout 不保留凭据 |
| 免费构建 | 标准 `xcode-27` 负责构建、测试、lint，标准 `ubuntu-latest` 负责许可证检查；不启用付费回退 |
| 检查工具 | 固定 SwiftLint 0.65.1 并验证下载摘要；保留现有 lint 规则与测试门槛 |
| 产物可追溯性 | IPA SHA-256 校验文件与构建 manifest；以真实检出的提交为来源，记录版本、工具链和依赖 |
| 草稿发布 | 新标签显式指向实际编译的提交；不覆盖已有标签或发布，普通 CI 不自动公开发布 |

现有 4.2.0 导航、App Audio Library、锁屏文字、备份恢复及写入守卫继续保留。没有把此次依赖更新宣称为全面性能优化，也没有把源码存在视为真机验证。

## 开源更新核查

核查日期为 2026-11-27。此表区分“核查过最新版本”与“本次实际引入”，避免把不同项目的最新提交整体覆盖到紫序。

| 项目 | 核查版本 / 提交 | 本次处理 |
|---|---|---|
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation/releases/tag/0.9.21) | 0.9.21；`e7048f0569f0ba37df26f8357f560b9d25e9a284` | 实际更新精确依赖和来源记录；保留应用级路径、体积、CRC、符号链接检查 |
| [GestaltX](https://github.com/huami1314/GestaltX) | 最新发布 v1.1.1；核查主线 `311f78999d9f5f062f7e3b4c6374684782be5382` | 4.x 已有经选择的上游移植；继续保留紫序的安全、备份和界面改动，不用整个上游树覆盖 |
| [Erosion-CN](https://github.com/Kianuni/Erosion-CN/releases/tag/v1.0.7) | v1.0.7；`094df45ddaedb044385ada4a4bf0f22e6a6252cb` | 新版主要涉及其去广告容器路径与应用映射；紫序没有对应功能，本维护更新不直接移植 |
| [SnapshotTesting](https://github.com/pointfreeco/swift-snapshot-testing/releases/tag/1.19.7) | 1.19.7 | 已是核查时最新版本，维持当前锁定 |

开源署名、直接依赖、设计参考和未集成项目的区别见 [OPEN_SOURCE_REFERENCES.md](OPEN_SOURCE_REFERENCES.md) 与 [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)。声音捕获/配对、去广告等新增产品工作不包含在本次维护版本中。

## 验收记录

提交前的 39 项 Python 一致性测试（本地化、发布准备、第三方署名）与许可证检查已通过；这不替代 Swift 编译和 XCTest。

下列证据必须关联到同一份待交付源码。历史 PR 的绿色检查、分支徽章、被取消的任务以及旧版 IPA 均不能替代这份记录。

| 验收项 | 本记录状态 | 证据入口 |
|---|---|---|
| 最终源码 SHA | 由构建 manifest / 集成 PR 记录 | [Pull requests](https://github.com/fafa888uk/LilaShift-3.0/pulls) |
| IPA 构建 | 以同一源码对应运行的结论为准 | [Build LilaShift IPA](https://github.com/fafa888uk/LilaShift-3.0/actions/workflows/build.yml) |
| Swift 单元测试 | 以对应运行日志的实际结果与计数为准 | [Run Swift Tests](https://github.com/fafa888uk/LilaShift-3.0/actions/workflows/run-swift-tests.yml) |
| SwiftLint | 以完成结果为准；排队/取消不记为通过 | [SwiftLint](https://github.com/fafa888uk/LilaShift-3.0/actions/workflows/swiftlint.yml) |
| 许可证检查 | 以同一源码对应运行的结论为准 | [Check Licenses](https://github.com/fafa888uk/LilaShift-3.0/actions/workflows/check-licenses.yml) |
| IPA 大小与 SHA-256 | 成功构建后随产物生成，不在源码中预填 | `build-manifest.json` 与 `.ipa.sha256` |
| 真机安装、eSIM、AI 与恢复 | 未验证 | 尚无本版本的真机证据 |
| 真机性能 | 未测量 | 不报告未经测量的提升百分比 |

已知的 4.2.0 / 旧 PR 测试计数不复用为 4.2.1 结果。新增或修改的回归测试以本次最终测试运行的实际计数为准。

## 获取与核对 IPA

成功的构建会上传 `LilaShift-4.2.1-<run_id>-<run_attempt>` 产物，保留 14 天。解压后有以下文件：

- `LilaShift_4.2.1.ipa`
- `LilaShift_4.2.1.ipa.sha256`
- `build-manifest.json`

manifest 记录真实源码提交、源码仓库、构建 ref、版本/构建号、构建时间、Xcode、runner 镜像、工作流链接、依赖锁定、IPA 大小及摘要。App 与分享扩展的版本一致性、ad-hoc 签名和 App Group 检查在打包中执行；这些检查不代替重新签名后的安装验证。

在 macOS / Linux 上，可在文件所在目录核对：

```bash
shasum -a 256 -c LilaShift_4.2.1.ipa.sha256
```

在 Windows PowerShell 中计算并与校验文件比较：

```powershell
Get-FileHash .\LilaShift_4.2.1.ipa -Algorithm SHA256
```

同时核对 manifest 的版本 `4.2.1`、构建号 `42000002` 与源码提交。构建通过后仍需按现有安装教程使用 LiveContainer 或合适的重签名方式；此 IPA 不包含个人开发者签名。

## 发布与剩余事项

普通 CI 只生成工作流产物。手动 **Prepare Draft Release** 工作流按实际源码提交创建草稿，拒绝覆盖现有标签或发布；草稿准备与公开发布是两个独立步骤。正式公开状态以 [Releases](https://github.com/fafa888uk/LilaShift-3.0/releases) 为准。

合并主线需要本次集成检查通过，并记录合并结果。旧草稿 PR #3–#19、余下历史 apply 工作流、分支/标签保护、架构重构、性能测量及真机验收继续按独立范围处理；本次维护更新不把这些事项自动标为完成。
