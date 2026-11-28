# W4 第三方来源声明（工作流 W4：MG 键值表）

> 本文件是 W4 工作流的工作声明，由总协调者后续并入
> `THIRD_PARTY_NOTICES.md`。W4 只移植了下面列明的两项内容，
> 其余部分（预设值、respring、机型欺骗、`bad_query` 后端、
> “27.x”兼容性标注）均未移植。

## 1. GoldensHQ/worstgestalt — GPL-3.0（不是 AGPL）

- 仓库：https://github.com/GoldensHQ/worstgestalt
- 许可证：**GNU General Public License v3.0**（README 称 or-later）。
  已逐字核对 `LICENSE` 原文（1,227 行，标准 GPL-3.0 文本，
  无任何 AGPL 条款、无“Affero”、无第 13 条网络使用条款）；
  GitHub API 许可证字段亦为 `gpl-3.0`。与 LilaShift 的 GPL-3.0 兼容。
- 作者署名：**awesomenull**；逃逸链（`worse_query`）署名
  **Taj C / forcequitOS**（见 worstgestalt README “Licenses” 节）。
- 移植范围：仅键值表数据文件
  `Sources/WorseGestalt/GestaltKeyMap.swift` 的数据内容——且 W4 没有
  直接复制该文件，而是用自写的生成器
  `scripts/generate_apple_wiki_key_table.py` 从 The Apple Wiki 原页面
  重新生成了 `GestaltX/AppleWikiKeyTable.swift`，并与上游文件逐项
  核对：943 个键全部一致，无新增、无缺失（见实施记录）。
  生成器本身是 LilaShift 原创代码（GPL-3.0-or-later）。
- 未移植：预设池（README 自述含 Nugget 的 AGPL 来源，逐条来源
  不明，不得整批照搬）、NeoSpring respring（无许可证）、
  device spoofing 预设（与 LilaShift“永不改 ProductType”红线冲突）、
  `bad_query` 后端（另行立项）、“27.x”兼容性标注（沿用 LilaShift
  自有版本哨兵，上限 27.3 beta 1）。

## 2. The Apple Wiki《List of MobileGestalt keys》— CC BY-SA 4.0

- 来源：https://theapplewiki.com/wiki/List_of_MobileGestalt_keys
- 许可证：键值表数据为 **CC BY-SA 4.0**（署名：The Apple Wiki 贡献者）。
  生成脚本 `tools/gen_keymap.py`（上游）头注自标
  `SPDX-License-Identifier: CC-BY-SA-4.0 for the map data`；
  W4 生成的 `GestaltX/AppleWikiKeyTable.swift` 文件头同样载明该声明。
- 移植范围：943 个键的人类可读名（全部）与英文描述（671 个键有描述，
  其余 272 个键在原页面即无描述，W4 未编造）。
- 再分发义务：**相同方式共享**——再分发本键值表时，须保留
  The Apple Wiki 署名与 CC BY-SA 4.0 声明，并以相同许可共享。
- 本表不含上游预设值，不含任何推测键名：每一行都来自上述原页面。

## 3. 中文翻译映射

- `GestaltX/MGKeyChineseNames.swift` 为 LilaShift 原创内容
  （GPL-3.0-only），122 个常用键的中文名与中文描述由人工逐条审校，
  不含机翻直入；未翻译的键标注“暂无中文名”，不编造翻译。
