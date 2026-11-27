# LilaShift 5.0.0 只读功能开发记录

2026-11-28 · 源码构建号 `50000001`。此分支用于审阅源码，尚未编译为 IPA，亦未在模拟器或真机上验收。

## 本分支功能

| 入口 | 功能 |
| --- | --- |
| 工具 → 诊断中心 → 只读工具 | 分类筛选与搜索，进入实时诊断、IPA 检查、配对文件检查、键名参考库和主题预览 |
| 实时诊断 | 根据 DeviceKit 数据识别 168 个 iPhone/iPad 标识符，显示当前系统版本、核心数、物理内存及系统端侧语言模型可用状态 |
| 实时性能 | App CPU 占用、常驻内存、磁盘总量及可用空间。页面挂起时停止采样 |
| 网络 | 本机网络路径、低数据模式及 Wi‑Fi、以太网和蜂窝接口收发速率。接口计数可能包含其他 App 的流量 |
| IPA 检查 | 检查主应用元数据，列出库、用途说明、签名资源及描述文件的存在状态 |
| 配对文件检查 | 本地读取 plist，检查标识字段、证书可解析性与私钥字段是否存在 |
| MobileGestalt 键名参考库 | 928 个键名和哈希，支持简体中文分类和搜索，显示可查的首次出现、移除和重新出现版本 |
| 个性化 → 主题预览 | 钱包卡面与锁屏数字键盘的应用内预览，支持三套配色及上滑过渡 |
| 壁纸库 → 图片详情 | 使用已导入图片展示可拖动的时钟与壁纸视差，遵循系统减弱动态效果设置 |

应用外卡面写入、系统锁屏主题安装、新设备自动配对、已配对设备在线信任检查、IPA 加密签名及 entitlements 验证、恶意软件判定与 App 级网络请求日志未纳入。端侧模型可用性仅反映 Foundation Models API 的当前状态。此分支复用现有外观选择和紫序玻璃组件，也保留了既有备份与恢复流程。新增界面支持简体中文和英文，其他语言使用英文回退。

## 上游核查

| 项目 | 核查版本或提交 | 许可及本次处理 |
| --- | --- | --- |
| [Camlo](https://github.com/Kianuni/Camlo) | v1.3.4，`be573b3` | GPL-3.0。应用内视差与动画独立实现 |
| [WQGuard](https://github.com/Kianuni/WQGuard) | v1.3.6，`307cf19` | MIT。IPA 结构只读检查基于现有 ZIPFoundation 独立实现 |
| [AppleLens](https://github.com/Kianuni/AppleLens) | v1.2.0，`3e49194` | MIT。原项目为 macOS 工具；此分支使用 iOS Foundation Models 和 Network API |
| [AirCard-iOS](https://github.com/Mak5er/AirCard-iOS) | v1.3.2，`40640c4` | MIT。卡面与键盘仅作应用内预览，无第三方资源 |
| [worstgestalt](https://github.com/GoldensHQ/worstgestalt) | Release 2.0，`c585074` | 主仓库 GPL-3.0，另有 MIT 组件。只读键名数据改用已获许可的 MGKeys |
| [idevice_pair](https://github.com/jkcoxson/idevice_pair) | v1.2.0，`fc18e59` | 未发现仓库级许可。独立实现配对文件字段和证书结构检查 |
| [DeviceKit](https://github.com/devicekit/DeviceKit) | 5.10.0，`fab82bd` | MIT。仅复用机型数据，附 MIT 全文 |
| [Pulse](https://github.com/kean/Pulse) | 5.2.3，`d766560` | MIT。未接入，本分支暂无可接入的 App HTTP 请求管道 |
| [GoldenNugget-mobile](https://github.com/GoldensHQ/GoldenNugget-mobile) | 标签 9.7.10，`2837e48` | AGPL-3.0。未引入源码，也未扩展系统写入 |
| [SystemMonitor](https://github.com/asido/SystemMonitor) | SystemMonitor-0.1.4，`184a43c` | MPL-2.0。基于 Apple API 与 Swift Charts 独立实现实时图表 |
| [MGKeys](https://github.com/PoomSmart/MGKeys) | `db9cf77` | MIT。此前已经复用 77 个键的元数据，本次新增完整只读目录 |

另核查 [Swift System Metrics](https://github.com/apple/swift-system-metrics)、[GestaltTweak](https://github.com/Rok574/GestaltTweak) 与 [libimobiledevice](https://github.com/libimobiledevice/libimobiledevice)。现有 Apple API 覆盖基础采样，移动系统修改代码和桌面通信栈均未引入。

本地通过 Python 测试、许可清单与 Swift 语法解析。Swift 单元测试、Xcode 构建和真机验收尚未运行。

两个数据表可分别通过 `scripts/generate-mg-reference.py` 与 `scripts/generate-device-models.py` 从固定提交再生成。涉及 iOS API 的编译、界面行为和采样能力仍需验证。
