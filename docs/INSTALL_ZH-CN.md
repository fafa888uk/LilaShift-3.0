# LilaShift 3.0 安装教程

> 版本：LilaShift 3.0.0-rc.1（**预发布，非稳定版**）
> 适用：iPhone / iPad，iOS / iPadOS 27.x（本机 MobileGestalt 访问）；最低可安装 iOS 26.0。
> 维护者：@steam8871 · 上游：huamidev/GestaltX v1.0.7
>
> **验证状态说明（请先读）：** 本教程的步骤按仓库文档（README、构建脚本
> `.github/scripts/build-ipa.sh`、工作流 `.github/workflows/build.yml`）与各工具的
> 公开说明整理。**本版 IPA（3.0.0-rc.1）尚未在真机上安装验证**——没有可用的真机。
> 下面每种方法都标了验证状态：标“待验证”的步骤，表示尚未用本版 IPA 在真机上
> 走通过，照做时请先备份、一步一步核对，遇到与教程不符的情况以屏幕实际提示为准，
> 并到 [GitHub Issues](https://github.com/fafa888uk/LilaShift-3.0/issues) 反馈。

## 目录

1. [开始之前：先弄清的 5 件事](#1-开始之前先弄清的-5-件事)
2. [第 1 步：打开 GitHub，找到发布页](#2-第-1-步打开-github找到发布页)
3. [第 2 步：下载 IPA](#3-第-2-步下载-ipa)
4. [第 3 步：选一种安装方式](#4-第-3-步选一种安装方式)
   - [方式 A：LiveContainer（推荐新手，不用重签）](#方式-a-livecontainer推荐新手不用重签)
   - [方式 B：AltStore](#方式-b-altstore)
   - [方式 C：SideStore](#方式-c-sidestore)
   - [方式 D：Sideloadly（电脑）](#方式-d-sideloadly电脑)
   - [方式 E：付费开发者证书 / Xcode 自签](#方式-e付费开发者证书--xcode-自签)
   - [方式 F：从源码自己构建](#方式-f从源码自己构建)
5. [第 4 步：首次打开，先读设备](#5-第-4-步首次打开先读设备)
6. [第 5 步：应用一键解锁（可选）](#6-第-5-步应用一键解锁可选)
7. [更新到新版本](#7-更新到新版本)
8. [证书过期 / 重装前：先导出备份](#8-证书过期--重装前先导出备份)
9. [常见错误速查](#9-常见错误速查)
10. [安全红线](#10-安全红线)

---

## 1. 开始之前：先弄清的 5 件事

### 1.1 IPA 不是 App Store 应用

IPA 是 iOS 应用安装包。LilaShift 不在 App Store 上架，你需要用下面第 4 节的
方法之一把它装到手机上。安装后首次打开时，系统会要求你信任开发者证书
（重签方式）或在容器内运行（LiveContainer 方式）。

### 1.2 不是所有机型、所有系统都能用全部功能

- **本机 MobileGestalt 访问需要 iOS / iPadOS 27.x。** iOS 26.x 上可以安装
  （最低 iOS 26.0），但本机访问会提示不支持，只能用本地 plist 编辑。
  详见 [COMPATIBILITY_ZH-CN.md](COMPATIBILITY_ZH-CN.md)。
- **eSIM 解锁需要 eSIM 硬件。** 只有带物理 eUICC 芯片的机型（iPhone Air、
  iPhone 18 系列等）才能加 eSIM。软件不能给没有 eSIM 芯片的设备变出一块芯片。
- **Apple Intelligence 取决于硬件与苹果服务。** 打开开关 ≠ 功能一定出现。
  详见 [COMPATIBILITY_ZH-CN.md](COMPATIBILITY_ZH-CN.md) 与
  [FAQ_ZH-CN.md](FAQ_ZH-CN.md)。
- **系统更新可能还原改动。** 升级 iOS 后如需继续使用，请先确认兼容性再升级，
  必要时重新应用。

### 1.3 先备份

应用前请先做一份设备备份（iCloud 或电脑备份）。LilaShift 自己也会在每次
写入前自动备份，但那份备份只记录它改动过的 MobileGestalt 值，不能替代整机
备份。备份与还原的完整说明见 [BACKUP_RESTORE_ZH-CN.md](BACKUP_RESTORE_ZH-CN.md)。

### 1.4 需要一个 App Group（重签方式）

LilaShift 由主应用 + 分享扩展组成，两者必须签入至少一个**相同的 App Group**
（`group.com.huami.gestultx`），分享扩展重签时必须保留。发布的 IPA 用 ad-hoc
签名嵌入了这些 entitlements，AltStore / SideStore 重签时可以识别。
LiveContainer 方式不需要重签，也就不需要你自己准备 App Group。
详见各方式的小节。

### 1.5 不要买来路不明的证书，不要交出 Apple ID 密码

- 不要向第三方签名服务购买证书，不要使用来路不明的“企业证书”。
- 安装过程**永远不需要**你把 Apple ID 密码告诉任何人、贴到任何聊天或网页里。
  正规工具（AltStore / SideStore / Sideloadly / Xcode）只会在你自己的设备或
  电脑上使用你的 Apple ID 登录苹果服务器。
- 详见第 10 节。

---

## 2. 第 1 步：打开 GitHub，找到发布页

1. 在手机或电脑浏览器打开
   [LilaShift 3.0.0-rc.1 发布页](https://github.com/fafa888uk/LilaShift-3.0/releases/tag/v3.0.0-rc.1)。
   - 如果链接打不开（预发布尚未发布），打开
     [全部 Releases 列表](https://github.com/fafa888uk/LilaShift-3.0/releases)，
     找标题含 `3.0.0-rc.1`、标着 **Pre-release** 的那一条。
2. 确认页面信息：
   - 标题：`LilaShift 3.0.0-rc.1`（或 `v3.0.0-rc.1`），并标有 **Pre-release**。
   - 说明里应写明这是预发布、构建提交与已知缺口。
   - 附件里应有 `LilaShift_3.0.0.ipa`。
3. 如果页面上只有旧版本（如 1.0.7 系列），说明 3.0.0-rc.1 还没发布——请等待，
   不要从不明渠道下载所谓“3.0”安装包。

> 官方更新通知只发在 Telegram 更新频道
> [LilaShift 紫序 · 更新公告](https://t.me/LilaShiftUpdates)（频道，只发公告，
> 不是讨论群）与本仓库 Releases 页。其他渠道的下载链接请勿轻信。

## 3. 第 2 步：下载 IPA

1. 在发布页点 `LilaShift_3.0.0.ipa` 下载。
   - 文件名：`LilaShift_3.0.0.ipa`（由构建脚本 `.github/scripts/build-ipa.sh`
     生成：`LilaShift_<版本>.ipa`）；包名 `com.huami.gestultx`，版本 `3.0.0`，
     build `30000002`，最低 iOS `26.0`。
   - 发布页如附带 SHA-256（发布清单 `release manifest`），请核对下载文件的
     SHA-256 与发布页公布的值一致；不一致请重新下载，不要安装。
2. **Safari 下载不完整的已知问题（未确认原因）：** 部分用户反馈 iOS 27 上用
   Safari 下载的 IPA 可能不完整，提示文件损坏或无法解压。遇到时：
   - 重新下载几次；
   - 仍不行换一个浏览器再试；
   - 不要用“修复损坏 IPA”的第三方工具处理。
3. 下载完成后先别急着装：确认文件后缀是 `.ipa`，且大小不是 0 KB 或明显过小
   （正常应为几 MB 以上；具体大小以发布页标注为准）。

---

## 4. 第 3 步：选一种安装方式

| 方式 | 需要电脑 | 需要证书 | 免费 Apple ID 可用 | App Group | 分享扩展 | 适合谁 |
| --- | --- | --- | --- | --- | --- | --- |
| A LiveContainer | 否（装容器本身可能需要一次侧载） | 否 | 是 | 容器内满足，无需自备 | 保留（容器内运行原 IPA） | 新手、没有电脑 |
| B AltStore | 首次需要电脑（装 AltStore） | 否（用个人 Apple ID） | 是（见免费账号限制） | 重签时由 AltStore 处理，需保留扩展 | 需保留 | 有电脑、想长期用 |
| C SideStore | 首次需要电脑（配对） | 否（用个人 Apple ID） | 是（见免费账号限制） | 重签时由 SideStore 处理，需保留扩展 | 需保留 | 不想依赖 AltServer |
| D Sideloadly | 是（Windows / macOS） | 否（用个人 Apple ID） | 是（见免费账号限制） | 重签时处理，需保留扩展 | 需保留 | 有电脑、图方便 |
| E 付费开发者证书 / Xcode | 是（macOS + Xcode） | 是（付费开发者账号） | 不适用 | 可在描述文件中配置 | 需保留 | 开发者、有付费账号 |
| F 从源码构建 | 是（macOS + Xcode） | 是（同 E） | 视账号而定 | 同 E | 同 E | 想自己编包 |

> 除方式 A 外，所有重签方式都要求：**主应用与分享扩展签入同一个 App Group，
> 且重签时保留分享扩展。** 丢了扩展或两边 App Group 不一致，会导致分享导入、
> 备份共享等功能异常。

---

### 方式 A：LiveContainer（推荐新手，不用重签）

- **验证状态：待验证。** LiveContainer 方式本身是仓库 README 记载的推荐方式
  （直接运行原始 IPA，无需重签、无需付费开发者账号），但**用 3.0.0-rc.1 的
  IPA 在真机上完整走通尚未验证**。
- **适合：** 没有电脑、不想折腾证书的新手。
- **需要电脑吗：** 安装 LiveContainer 本身通常需要一次侧载（可用 AltStore /
  SideStore / Sideloadly 等方式装 LiveContainer）；装好之后再装 LilaShift
  就不需要电脑了。
- **需要证书吗：** LilaShift 本身不需要重签、不需要证书。
- **免费账号限制：** 不适用（不走 Apple 个人签名）。
- **App Group：** 容器内运行原始 IPA，满足要求，无需自备。
- **分享扩展：** 保留，随原 IPA 一起在容器内运行。

**步骤：**

1. 先在设备上装好 LiveContainer（见 LiveContainer 官方仓库
   [khanhduytran0/LiveContainer](https://github.com/khanhduytran0/LiveContainer)
   的安装说明；装 LiveContainer 的那一步本身可能需要电脑侧载一次）。
2. 把第 3 步下载的 `LilaShift_3.0.0.ipa` 传到手机（隔空投送、文件 App、
   或从手机浏览器直接下载到“文件”）。
3. 在 LiveContainer 里选择安装 IPA，找到 `LilaShift_3.0.0.ipa` 并安装。
4. 回到主屏幕打开 LilaShift（图标为猫照片），继续第 5 步。
5. 如需 JIT 或其他 LiveContainer 高级功能，请按 LiveContainer 自身文档操作，
   本教程不展开。

**常见错误：**

- LiveContainer 里打不开 IPA：先确认 IPA 下载完整（见第 3 步第 2 条），
  重新下载后再试。
- 打开 LilaShift 提示读不到设备：先确认系统是 iOS / iPadOS 27.x；26.x 上
  本机访问本来就不支持（见 [COMPATIBILITY_ZH-CN.md](COMPATIBILITY_ZH-CN.md)）。

---

### 方式 B：AltStore

- **验证状态：待验证。** AltStore 重签流程按 AltStore 公开说明与本仓库
  README（IPA 含 ad-hoc entitlements、可被 AltStore 识别）整理，
  **尚未用 3.0.0-rc.1 的 IPA 在真机上验证**。
- **适合：** 有电脑、希望装好后手机端可直接刷新续签的用户。
- **需要电脑吗：** 首次安装 AltStore 需要电脑（AltServer，Windows / macOS）；
  之后同一 Wi-Fi 下可用 AltStore 自行刷新。
- **需要证书吗：** 不需要另外购买证书；用你自己的 Apple ID 以个人开发者方式
  签名（免费账号即可，见限制）。
- **免费账号限制（按 Apple 免费个人账号的公开规则，待用本版 IPA 核实）：**
  证书有效期 7 天，到期前需在同一 Wi-Fi 下用 AltStore 刷新；同一账号同时
  有效的自签应用数量有限（一般为 3 个）。过期后应用打不开，直到重新签名。
- **App Group：** 重签时 AltStore 会处理 IPA 内嵌的 entitlements；请勿手动
  删改 entitlements。
- **分享扩展：** 重签时必须保留，不可去掉。

**步骤：**

1. 在电脑上装 AltServer（见 AltStore 官网说明），手机与电脑连同一 Wi-Fi，
   按 AltStore 官方步骤把 AltStore 装到手机上。
2. 把 `LilaShift_3.0.0.ipa` 传到手机。
3. 在手机上用 AltStore 打开 IPA 安装（通过“文件”分享到 AltStore，或在
   AltStore 内选择 IPA 文件）。
4. 安装时 AltStore 会用你的 Apple ID 重签。**只在 AltStore / 苹果官方登录
   界面输入 Apple ID，绝不在其他页面输入密码。**
5. 首次打开前，去「设置 → 通用 → VPN 与设备管理」信任开发者证书（如有提示）。
6. 打开 LilaShift，继续第 5 步。
7. 到期前（7 天内）在同一 Wi-Fi 下打开 AltStore 刷新续签。

**常见错误：**

- 提示证书过期 / 应用闪退打不开：多半是 7 天到期未刷新，重新签名即可。
- 提示 App Group 相关错误（如 `MobileGestalt access was denied`）：检查
  重签是否保留了分享扩展、App Group 是否一致；不要用去掉扩展的精简包。
- 刷新失败：确认手机与装有 AltServer 的电脑在同一 Wi-Fi，且 AltServer 在运行。

---

### 方式 C：SideStore

- **验证状态：待验证。** SideStore 重签流程按 SideStore 公开说明与本仓库
  README 整理，**尚未用 3.0.0-rc.1 的 IPA 在真机上验证**。
- **适合：** 不想长期依赖 AltServer、接受首次配对稍复杂一点的用户。
- **需要电脑吗：** 首次配对需要电脑；配对后可用 SideStore 自行刷新
  （具体以 SideStore 当前版本说明为准）。
- **需要证书吗：** 不需要另外购买证书；用你自己的 Apple ID 以个人开发者方式签名。
- **免费账号限制（按 Apple 免费个人账号的公开规则，待用本版 IPA 核实）：**
  与 AltStore 相同，证书有效期 7 天，需定期刷新；同时有效的自签应用数量有限。
- **App Group：** 重签时 SideStore 会处理 IPA 内嵌的 entitlements；请勿手动删改。
- **分享扩展：** 重签时必须保留，不可去掉。

**步骤：**

1. 按 SideStore 官方说明完成首次配对（需要电脑）。
2. 把 `LilaShift_3.0.0.ipa` 传到手机，用 SideStore 打开并安装。
3. 安装时 SideStore 会用你的 Apple ID 重签。**只在 SideStore / 苹果官方登录
   界面输入 Apple ID。**
4. 首次打开前按提示信任开发者证书（如有）。
5. 打开 LilaShift，继续第 5 步。
6. 到期前用 SideStore 刷新续签。

**常见错误：** 同方式 B（证书过期、App Group / 扩展缺失、刷新网络问题）。

---

### 方式 D：Sideloadly（电脑）

- **验证状态：待验证。** Sideloadly 流程按其公开说明整理，
  **尚未用 3.0.0-rc.1 的 IPA 在真机上验证**。
- **适合：** 有 Windows / macOS 电脑、想一次装好、不介意每次续签都连电脑的用户。
- **需要电脑吗：** 是，每次安装 / 续签都需要电脑 + 数据线（或按其说明用 Wi-Fi）。
- **需要证书吗：** 不需要另外购买证书；用你自己的 Apple ID 以个人开发者方式签名。
- **免费账号限制（按 Apple 免费个人账号的公开规则，待用本版 IPA 核实）：**
  证书有效期 7 天，到期需连电脑重新签名；同时有效的自签应用数量有限。
- **App Group：** Sideloadly 重签时会处理 IPA 内嵌的 entitlements；
  如其提供“注入 / 精简”选项，**不要去掉分享扩展**。
- **分享扩展：** 重签时必须保留。

**步骤：**

1. 在电脑上装 Sideloadly（见其官网），手机连电脑并信任此电脑。
2. 在 Sideloadly 里选择 `LilaShift_3.0.0.ipa`，输入你的 Apple ID，
   按提示完成签名与安装。**只在 Sideloadly 本地界面输入 Apple ID。**
3. 手机上按提示信任开发者证书（如有）。
4. 打开 LilaShift，继续第 5 步。
5. 7 天到期前重新连电脑签名一次。

**常见错误：**

- 登录失败 / 报错：确认 Apple ID 与密码无误、网络正常；开启了双重认证的账号
  按 Sideloadly 提示完成验证（验证码只填在苹果官方弹窗里）。
- 安装后闪退：多半是证书过期，重新签名。
- 分享导入不可用：检查重签是否保留了分享扩展。

---

### 方式 E：付费开发者证书 / Xcode 自签

- **验证状态：待验证。** 流程按本仓库 README 与 Xcode 公开说明整理，
  **尚未用 3.0.0-rc.1 在真机上验证**。
- **适合：** 有 Apple Developer Program 付费账号（年费）的开发者。
- **需要电脑吗：** 是（macOS + Xcode）。
- **需要证书吗：** 是（付费开发者账号的开发证书 + 描述文件）。
- **免费账号限制：** 不适用（付费账号证书有效期通常为 1 年，以苹果实际签发为准）。
- **App Group：** 描述文件须包含至少一个可用 App Group，且主应用与分享扩展
  使用同一个（`group.com.huami.gestultx`）。
- **分享扩展：** 必须保留并与主应用签入同一个 App Group。

**步骤：**

1. 在 Apple Developer 后台确认描述文件包含 App Group
   `group.com.huami.gestultx`（或你自己的同名配置——改动 App Group 标识
   须同步改工程配置，**待验证**，不建议自行改）。
2. 用 Xcode 打开本仓库工程（或用已签名的 IPA 重签工具），选择你的开发证书
   与描述文件，为主应用与分享扩展签名。
3. 安装到设备，信任证书（如有提示）。
4. 打开 LilaShift，继续第 5 步。

**常见错误：**

- 描述文件没有 App Group：签名会通过，但运行时 App Group 不可用，
  表现为 `MobileGestalt access was denied` 或分享导入失败。解决：补 App Group
  后重新签名。
- 主应用与扩展 App Group 不一致：同上，须保持一致。

---

### 方式 F：从源码自己构建

- **验证状态：待验证（构建流程本身以 CI 为准）。** CI（Build LilaShift IPA
  工作流，`.github/workflows/build.yml`）每次推送都会从源码构建 IPA；
  本地构建步骤尚未在本机验证。
- **适合：** 想核对源码再自己编包的用户。
- **需要电脑吗：** 是（macOS + Xcode，CI 用 `xcode-27` runner）。
- **需要证书吗：** 本地编包签名需要证书（同方式 E）；只编不签的产物无法直接安装。

**步骤：**

1. 克隆仓库并切换到 `feature/lilashift-3.0-dashboard` 分支（或打了
   `v3.0.0-rc.1` 标签的提交）。
2. 用 Xcode 打开 `GestaltX.xcodeproj`，选择你的开发团队与描述文件
   （须含 App Group，见方式 E）。
3. 构建并安装；或按 `.github/scripts/build-ipa.sh` 的做法打包 IPA 后再用
   上述任一方式安装。
4. 也可以直接用 CI 产物：GitHub Actions 的 Build LilaShift IPA 运行页
   下载名为 `LilaShift-<版本>` 的 artifact（保留 14 天）。

---

## 5. 第 4 步：首次打开，先读设备

1. 打开 LilaShift，首页是 3.0 轻量首页：先显示设备读取状态与待应用更改数量。
2. 点 **Read Device**（读取设备），等读取完成。读取进度由真实读取状态驱动，
   不会凭空显示百分比。
3. 读取完成后：
   - 首页会显示设备概况（机型、系统版本等）；
   - 打开 **China Unlock** 可看到 10 项内容的当前状态；
   - 打开功能目录可按 11 个分类浏览 53 项功能，每项有 8 状态兼容性标识
     （原生支持 / 可改 / 已启用 / 已暂存 / 需重启 / 未验证 / 不支持 / 读取失败）。
4. 如果读取失败或某项显示“读取失败 / 未验证”，先不要应用任何改动，
   见 [TROUBLESHOOTING_ZH-CN.md](TROUBLESHOOTING_ZH-CN.md)。

## 6. 第 5 步：应用一键解锁（可选）

> 只在你确认需要时做。应用前请再读一遍
> [BACKUP_RESTORE_ZH-CN.md](BACKUP_RESTORE_ZH-CN.md) 与
> [COMPATIBILITY_ZH-CN.md](COMPATIBILITY_ZH-CN.md)。

1. 打开 **China Unlock**，确认 10 项内容：eSIM 两项开关、地区码 `LL`、
   7 项 Apple Intelligence 能力。
2. 点暂存，逐项核对前后对比值（Diff 预览）。eSIM 缓存布局校验不通过时
   整组会停住并显示原因——此时不要强行操作，地区码与 AI 仍可单独设置。
3. 确认无误后点应用。应用过程会依次做：自动备份 → 写入 → 写回校验 → 完成。
4. 应用完成后**冷重启**：滑动关机，等黑屏后再开机。只刷新 SpringBoard
   对 eSIM 不够（基带守护进程不会重载缓存）。
5. 开机后去系统「设置」检查 eSIM 与 Apple Intelligence 是否出现。
6. 想全部撤销：用一键还原，从备份恢复全部 10 项（含义与限度见备份文档）。

## 7. 更新到新版本

1. 等新版本发布（Telegram 更新频道与 Releases 页会公告）。
2. **更新前先导出备份**（见第 8 节）：卸载 App 会删掉容器内的备份。
3. 下载新版 IPA，按原来那一节的方式重新安装。
   - LiveContainer：直接安装新版 IPA 覆盖。
   - 重签方式：重新签名安装；证书未过期时一般可直接覆盖安装。
4. 打开新版，先点 **Read Device**，核对状态后再决定是否重新应用。
5. 系统更新（iOS 升级）后：先确认新系统是否兼容（频道与 Releases 公告），
   再决定是否升级；升级后如改动被还原，按第 6 节重新应用。

## 8. 证书过期 / 重装前：先导出备份

- 免费个人证书 7 天过期后，应用打不开；**卸载 App 会删掉 App 容器内的备份**
  （出厂金库除外——见备份文档）。
- 所以：证书到期前、重装前、换机前，务必先在 LilaShift 备份页**导出备份**，
  保存到“文件”或其他安全位置。
- 续签（AltStore / SideStore / Sideloadly 刷新）本身不删数据，但为防万一，
  刷新前也建议先导出一份。

## 9. 常见错误速查

| 现象 | 可能原因 | 做法 |
| --- | --- | --- |
| IPA 下载后提示损坏 / 无法解压 | Safari 下载不完整（已知反馈，未确认原因） | 重新下载几次，换浏览器再试 |
| 安装后打开闪退 | 证书过期（免费账号 7 天） | 重新签名 / 刷新 |
| 提示“无法验证 App”/ 未受信任的开发者 | 证书未信任 | 设置 → 通用 → VPN 与设备管理 → 信任 |
| `MobileGestalt access was denied` | App Group 不可用或不一致 | 检查重签是否保留分享扩展、主应用与扩展 App Group 是否相同；LiveContainer 方式下确认系统为 iOS 27.x |
| 读取失败 / 某项“未验证” | 系统版本不支持或读取异常 | 确认 iOS 27.x；重启 App 再读一次；仍失败见故障排查文档 |
| eSIM 菜单不出现 | 未冷重启 / 只改了地区码 / 改了机型标识 / 无 eUICC 硬件 | 冷重启；确认 10 项都应用了；绝不要改 `ProductType`；无硬件则无法开通 |
| AI 菜单不出现 | 模型未下载完 / 代理规则 / 地区设置 | 见 [TROUBLESHOOTING_ZH-CN.md](TROUBLESHOOTING_ZH-CN.md) |

## 10. 安全红线

- **不要买证书。** 任何“9.9 元企业证书”“永久签名”都是高风险：证书随时可被
  苹果吊销，且可能被用来分发篡改过的应用。
- **不要交 Apple ID 密码。** 安装全程不需要把密码告诉任何人、贴到聊天、
  网页或发给“客服”。只在苹果官方登录界面或你自己电脑上的正规工具里输入。
- **不要从不明渠道下载 IPA。** 只从本仓库 Releases 页下载；核对文件名
  `LilaShift_3.0.0.ipa` 与发布页公布的 SHA-256。
- **只在自己持有或已获授权的设备上使用。** 修改 MobileGestalt 可能导致
  系统不稳定，严重时需要恢复设备。
- **反馈时不要贴个人资料。** 报 Bug 时不要贴序列号、UDID、IMEI、Apple ID、
  账号密钥或完整日志里的个人标识。见 [COMMUNITY.md](../COMMUNITY.md)。

---

相关文档：[使用指南](USER_GUIDE_ZH-CN.md) · [兼容性](COMPATIBILITY_ZH-CN.md) ·
[备份与还原](BACKUP_RESTORE_ZH-CN.md) · [故障排查](TROUBLESHOOTING_ZH-CN.md) ·
[常见问题](FAQ_ZH-CN.md) · [功能清单](FEATURES_ZH-CN.md)
