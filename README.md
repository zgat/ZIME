# ZIME

ZIME 是一款面向 Apple Silicon、macOS 13 及以上版本的本地优先双语输入法。
它把候选原文和翻译分开显示：候选主文本是实际输入内容，灰色副文本是本地
释义；只有用户主动切换到译文候选并确认时，译文才会上屏。

## 功能

- 两个 macOS 输入源：“ZIME 简体中文”和“ZIME 繁體中文”，共用设置和学习数据；
- 中文全拼、多字词、首字母缩写、保守模糊音与错序纠正；
- 中文模式优先可靠中文词与已学词，简拼 `key` 默认优先“可以”；仅在中文
  匹配较弱时让常见英文优先，Shift 切换后的英文模式保持英文排序；
- 智能英文补全、拼写纠错、多词候选、常用缩写、IPA 和下一词预测；
- 每行候选都显示译文，默认竖排，候选数量下拉框可选 3–9；
- 候选固定按页显示，不再提供多页展开模式；Local Data 折叠项的整个标题行都可点击；
- 英文候选显示中文释义，中文候选显示英文释义，内置 CC-CEDICT 中英词典；
- 中文本地释义按地区筛选：简体为通用 + 大陆，繁体为通用 + 港澳台及新马；
- 同义译文去重，候选行保留辨义限定，拼音引用及长篇说明放入悬停详情；
- 简繁词条分别匹配：“你／妳”不混用，“发”的發／髮不同词义均保留；
- 本地用户词频、自动组词、上下文排序、Emoji 与本地词库缓存；
- 轻按 Shift 切换中文/智能英文，Caps Lock 保持原始 ASCII；
- 候选翻页用 `-` 上一页、`=` / `+` 下一页，到首尾页停留，不把符号上屏；
- 默认仅保留 macOS 输入源菜单，不再另建中英文状态栏图标；
- 原生设置界面，以及给高级用户的 Rime YAML 投影。
- 八套浅色/深色配色；主题只换颜色，选中效果和窗口角形独立设置；
- 候选词与设置预览使用相同常规字重，翻译不再触发加粗。

![中英文候选逐行翻译](resources/readme/bilingual-features.png)

默认按 Tab 进入译文候选，按数字键或回车确认译文；再次按 Tab 或 Escape 回到
原文候选。切换键可改为 Option-Return，译文确认键可改为空格。没有进入译文
候选状态时，翻译仅用于展示，不会自动附加到输入内容。

![地区释义与澄蓝配色](resources/readme/regional-glosses.png)

0.1.5 将原「原生玻璃」更名为「雾灰」，原「macOS」更名为「澄蓝」，优化中性
底色、细边框和选中配色。两者是 ZIME 自绘候选窗的配色，不是系统输入法的
原生候选组件。旧主题 ID 保留，不会重置已选主题。

「设置 → 外观 → 候选窗口」可分别选择「整行变色／下划线」和「圆角／直角」。
整行选中背景跟随窗口角形；下划线使用可见度更高的强调色。主题小样与实际
候选窗跟随这些选项，切换配色不会改字体、选中效果、角形或材质。外观模式
仍可选择系统、浅色或深色；无需重新编译词库。

![独立选中效果与角形](resources/readme/appearance-controls.png)

地区分组是产品偏好，并不把简繁字形等同于地区；
新加坡、马来西亚按此产品的约定归入繁体组。筛选依据明确词典标签，未标注
地区的释义保留，不凭句子提到的地名猜测用法。词库并非完整的地区专用词典。

0.1.4 保留 CC-CEDICT 原始简繁字形、读音和完整释义，展示时区分词义与注释。
例如“你”显示 `you (informal)`，“妳”显示 `you (female)`；“您”的拼音引用、
地区用字段落等仍可在悬停详情里查看。`capital (city)` 等辨义限定不删除，
未知格式不强行精简。普通输入仍只上屏候选原文；Tab 译文候选保留完整释义，
不会把显示层的文字缩减当作对上屏文本的修改。

## 离线与隐私

中英文词典、反向索引、纠错、预测和学习均在本机运行。完整交付包内含
CC-CEDICT 124,988 条源词条、四类带清单校验的离线数据包和万象 LTS 模型。

0.1.1 新增独立“翻译”设置页，可接入 OpenAI 兼容接口、DeepL、百度、腾讯。
云翻译默认关闭；只有开启并保存后，才发送当前页缺少本地译文的候选词，
不发送剪贴板、文档上下文或输入历史。API 可能收费，密钥仅保存在本机钥匙串。
“测试连接”按钮会明确发送固定单词 `hello`，不会自动开启云翻译。

## 安装与构建

安装步骤见 [ZIME 安装说明](docs/ZIME-INSTALL.md)，实现边界和行为合同见
[ZIME 设计说明](docs/ZIME.md)。

准备锁定的依赖和数据后，可执行：

```sh
no_download=1 ./action-build.sh release
./tests/verify_zime_translation.sh
./tests/verify_swift_units.sh
./tests/verify_rime_runtime.sh --zime-bilingual-probe
./tests/verify_english_data_projection.sh
```

生产标识 App 构建完成后，用以下命令生成带完整离线数据的 ZIP 和当前用户 PKG：

```sh
scripts/build-zime-delivery /absolute/path/to/ZIME.app /absolute/output/directory
```

开发预览包采用可验证的 Ad-hoc App 签名，PKG 未使用 Apple Developer ID 签名，
也未经过公证；它不能被描述为正式公证发行版。

0.1.1 的验证范围、词库比较和已知限制见
[验证记录](docs/ZIME-0.1.1-VALIDATION.md)。
0.1.2 的翻页边界与菜单栏修复见 [验证记录](docs/ZIME-0.1.2-VALIDATION.md)。
0.1.3 的地区释义与 macOS 配色见 [验证记录](docs/ZIME-0.1.3-VALIDATION.md)。
0.1.4 的词条归属、译义去重与注释分层见 [验证记录](docs/ZIME-0.1.4-VALIDATION.md)。
0.1.5 的配色、字重与独立外观选项见 [验证记录](docs/ZIME-0.1.5-VALIDATION.md)。
0.1.6 的中文简拼优先与跨语言学习排序见 [验证记录](docs/ZIME-0.1.6-VALIDATION.md)。
0.1.7 的候选展开代码清理与设置点击修复见 [验证记录](docs/ZIME-0.1.7-VALIDATION.md)。
0.1.8 修复中文模式下英文选词不学习的问题；中英文可随实际选词次数双向调整，记录跨重启保留。见 [验证记录](docs/ZIME-0.1.8-VALIDATION.md)。
0.1.9 将两种输入模式的学习隔离：中文模式内中英文一起排序，独立英文模式另行训练，互不影响。见 [验证记录](docs/ZIME-0.1.9-VALIDATION.md)。

## 上游与许可证

ZIME 基于 [Linnet](https://github.com/Ares-X/Linnet) 的
`9334c4ac563b0dad341c3661c59a4e4467b01e36` 修改，并间接使用 Squirrel、
librime、万象、RIME-LMDG、rime-ice 和 HallelujahIM。修改后的组合源码按
[GPL-3.0-or-later](LICENSE.txt) 发布；数据与第三方代码的精确来源和许可证见
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 与 `LICENSES/`。
