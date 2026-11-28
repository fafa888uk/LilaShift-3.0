# LilaShift 5.0.0 · 重大更新与验收记录

准备日期：2026-11-28（Asia/Shanghai）。应用版本 `5.0.0`，构建号 `50000000`，预期文件名 `LilaShift_5.0.0.ipa`。

本文随构建源码冻结，记录更新范围和验收入口。最终源码 SHA、实际 CI 结果和下载位置以本次集成 PR 与构建 manifest 为准；本文不预填运行结果，准备源码不等于已经公开发布。此前已发布版本为 [v4.2.0](https://github.com/fafa888uk/LilaShift-3.0/releases/tag/v4.2.0)，其源码提交为 `3152fc7c49ccb00f80f97da90666a65fb66a6d89`，build `42000001`。4.2.1 维护更新（ZIPFoundation 0.9.21、本地化补齐、治理/CI）已包含在本版本基线中，未单独发布。

## 本次更新

| 范围 | 实际改动 |
|---|---|
| 设备诊断（W1） | 新增只读诊断：屏幕物理指标、生物识别状态、低电量模式、亮度、可用磁盘容量；iPhone 机型表（iPhone 6 至 18 Pro Max，含 iPhone Air `iPhone18,4`）转录自 DeviceKit 5.10.0（MIT），无新增依赖 |
| 结构化日志（W2） | 新增分级操作日志：搜索、筛选、JSON/纯文本导出；只记录本 App 自身操作事件，不含网络请求记录 |
| IPA 安全审计（W3） | 新增 Mach-O 解析、代码签名 SuperBlob/Slot 5/Slot 7 分析、IPA 包扫描、威胁库四级裁决、CVE 雷达（13 项分数按 NVD 重核）、报告导出；设计借鉴 WQGuard v1.3.6（MIT） |
| MG 键值表（W4） | 新增 943 键 Apple Wiki 键值表（与 worstgestalt 逐键核对，GPL-3.0）与 122 个已审校简体中文名；自有生成器重新生成 |
| 网络探针（W5） | 新增无特权 ICMP ping/traceroute 与 RIPEstat 出口 ASN/BGP 查询；设计借鉴 ip-tools（MIT）；私网地址事前拒绝 |
| 文件浏览（W6） | 新增多选批量操作、文件夹递归导入、只读跨应用浏览与缓存统计、开屏广告路径表（全部“待核实”）；机制借鉴 Erosion-CN v1.0.8 / WQFiles（GPL-3.0）；未做批量删除、广告锁定与跨应用清理 |
| 导航接线 | 5 个新页面加入功能目录（页面项 13 → 18，总数 59 → 64）与首页诊断分区（11 → 15）；MG 键值表增强现有字段编辑器 |
| 本地化 | 补齐 Wave 1 缺失的 281 个字符串，覆盖全部 10 个语种（共 1934 键）；12 个带首尾空格的片段键在代码中修复 |
| 许可证 | Wave 1 第三方声明并入 `THIRD_PARTY_NOTICES.md`（§12），新增 3 份 bundled MIT 文本；应用内声明保持字节一致 |
| 版本与文档 | 版本 4.2.1 → 5.0.0，构建号 42000002 → 50000000；README 新增版本徽章；中、英、日三语文档同步 |
| 免费构建 | 标准 `xcode-27` 负责构建、测试、lint，标准 `ubuntu-latest` 负责许可证检查；不启用付费回退 |

现有 4.2.x 导航、App Audio Library、锁屏文字、一键解锁、备份恢复及写入守卫继续保留。没有把此次新增功能宣称为已真机验证，也没有把源码存在视为性能提升。

## 开源更新核查

核查日期为 2026-11-28。此表区分“核查过最新版本”与“本次实际引入”，避免把不同项目的最新提交整体覆盖到紫序。完整审计见 `audit/`，完整声明见 `THIRD_PARTY_NOTICES.md` §12 与 `docs/OPEN_SOURCE_REFERENCES.md`。

| 项目 | 核查版本 / 提交 | 本次处理 |
|---|---|---|
| [DeviceKit](https://github.com/devicekit/DeviceKit) | 5.10.0；主线 `fab82bd` | 仅转录机型映射与屏幕参数；无代码复制，无新增依赖 |
| [WQGuard](https://github.com/Kianuni/WQGuard) | v1.3.6；`307cf19f37864fa45bd1216bcd2ac908e92a9435` | 设计精简重写（Mach-O/CSBlob/扫描/威胁库/CVE 雷达结构）；CVE 分数按 NVD 重核，未采用上游分数 |
| [worstgestalt](https://github.com/GoldensHQ/worstgestalt) | 主线（GPL-3.0，已逐字核对 LICENSE，非 AGPL） | 仅键值表数据，自有生成器从 The Apple Wiki 重生成，943 键逐项核对一致 |
| [The Apple Wiki](https://theapplewiki.com/wiki/List_of_MobileGestalt_keys) | 2026-11-28 修订版 | 943 键可读名 + 671 条描述；CC BY-SA 4.0，相同方式共享 |
| [ip-tools](https://github.com/ahmadrezaei/ip-tools) | 主线 `6ea8045ba0efc40ff6168e49ddbe07338128cf60` | NetCore 设计重写（ICMP 编解码、无特权 socket、ping/tracer、RIPEstat 端点）；无文件逐字复制 |
| [PingKit](https://github.com/gewill/PingKit) | 主线 `be85db219ca7d111e5c943e254238cdb248a6267` | 仅设计参考（发送失败计入丢包等）；无代码复制 |
| [Erosion-CN](https://github.com/Kianuni/Erosion-CN) | v1.0.8（开屏路径 v1.0.6/v1.0.7） | W6 文件浏览机制重写；开屏路径全部“待核实”，未移植批量删除、广告锁定与清理 |
| [WQFiles](https://github.com/kolbicz/WQFiles) | 主线 `d4aae98ca01d416ea23c60a9fe5c074b5b810798` | W6 只读跨应用浏览与缓存统计机制重写；未移植任何清理 |
| [Camlo](https://github.com/Kianuni/Camlo) / [WQGuard](https://github.com/Kianuni/WQGuard) / [AppleLens](https://github.com/Kianuni/AppleLens) | 已审核（见 `audit/`） | Wave 2 范围，不在本版本内 |
| [GoldenNugget-mobile](https://github.com/GoldensHQ/GoldenNugget-mobile) | AGPL-3.0 | 暂缓：5 组功能须三项评审，不得移植代码 |
| [idevice_pair](https://github.com/jkcoxson/idevice_pair) | 已审核（见 `audit/`） | 暂缓：结构校验仅 airlift 后有意义 |

开源署名、直接依赖、设计参考和未集成项目的区别见 [OPEN_SOURCE_REFERENCES.md](OPEN_SOURCE_REFERENCES.md) 与 [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)。Wave 2（AppleLens 诊断子集、实时监控图表、Camlo 创作子集、AirCard 钱包主题、Liquid Glass 界面、上游配对/通知声音捕获）不包含在本版本中。

## 验收记录

提交前的 46 项 Python 一致性测试（本地化、发布准备、第三方署名）与许可证检查已通过；这不替代 Swift 编译和 XCTest。新增 XCTest 173 个（W1–W6 各路）+ Python 生成器测试 7 个 + 接线测试 6 个，本地无 Xcode 工具链，编译与 XCTest 须走 CI。

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

已知的 4.2.0 / 4.2.1 测试计数不复用为 5.0.0 结果。新增或修改的回归测试以本次最终测试运行的实际计数为准。

## 获取与核对 IPA

成功的构建会上传 `LilaShift-5.0.0-<run_id>-<run_attempt>` 产物，保留 14 天。解压后有以下文件：

- `LilaShift_5.0.0.ipa`
- `LilaShift_5.0.0.ipa.sha256`
- `build-manifest.json`

manifest 记录真实源码提交、源码仓库、构建 ref、版本/构建号、构建时间、Xcode、runner 镜像、工作流链接、依赖锁定、IPA 大小及摘要。App 与分享扩展的版本一致性、ad-hoc 签名和 App Group 检查在打包中执行；这些检查不代替重新签名后的安装验证。

在 macOS / Linux 上，可在文件所在目录核对：

```bash
shasum -a 256 -c LilaShift_5.0.0.ipa.sha256
```

在 Windows PowerShell 中计算并与校验文件比较：

```powershell
Get-FileHash .\LilaShift_5.0.0.ipa -Algorithm SHA256
```

同时核对 manifest 的版本 `5.0.0`、构建号 `50000000` 与源码提交。构建通过后仍需按现有安装教程使用 LiveContainer 或合适的重签名方式；此 IPA 不包含个人开发者签名。

未完成真机验证时，本版本发布为预发布，不得虚假标注为已验证稳定版；关键测试失败时禁止正式发布。

## 发布与剩余事项

普通 CI 只生成工作流产物。手动 **Prepare Draft Release** 工作流按实际源码提交创建草稿，拒绝覆盖现有标签或发布；草稿准备与公开发布是两个独立步骤。正式公开状态以 [Releases](https://github.com/fafa888uk/LilaShift-3.0/releases) 为准。

合并主线需要本次集成检查通过，并记录合并结果。Wave 2、真机验收、旧草稿 PR #3–#19、余下历史 apply 工作流、分支/标签保护、架构重构、性能测量继续按独立范围处理；本次版本更新不把这些事项自动标为完成。
