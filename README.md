# ZIME

ZIME 是一款面向 Apple Silicon、macOS 13 及以上版本的本地优先双语输入法。
它把候选原文和翻译分开显示：候选主文本是实际输入内容，灰色副文本是本地
释义；只有用户主动切换到译文候选并确认时，译文才会上屏。

## 功能

- 两个 macOS 输入源：“ZIME 简体中文”和“ZIME 繁體中文”，共用设置和学习数据；
- 中文全拼、多字词、首字母缩写、保守模糊音与错序纠正；
- 智能英文补全、拼写纠错、多词候选、常用缩写、IPA 和下一词预测；
- 英文候选显示中文释义，中文候选显示英文释义；
- 本地用户词频、自动组词、上下文排序、Emoji 与本地词库缓存；
- 轻按 Shift 切换中文/智能英文，Caps Lock 保持原始 ASCII；
- 原生设置界面，以及给高级用户的 Rime YAML 投影。

默认按 Tab 进入译文候选，按数字键或回车确认译文；再次按 Tab 或 Escape 回到
原文候选。切换键可改为 Option-Return，译文确认键可改为空格。没有进入译文
候选状态时，翻译仅用于展示，不会自动附加到输入内容。

## 离线与隐私

中英文释义、反向索引、纠错、预测和学习均在本机完成。0.1 版只装载
`ZIMENullCloudTranslationProvider`，候选翻译路径不包含网络客户端，也不会发送
按键、候选、词典或学习数据。完整交付包内含四类带清单校验的离线数据包和
万象 LTS n-gram 语法模型。

## 安装与构建

安装步骤见 [ZIME 安装说明](docs/ZIME-INSTALL.md)，实现边界和行为合同见
[ZIME 设计说明](docs/ZIME.md)。

准备锁定的依赖和数据后，可执行：

```sh
no_download=1 ./action-build.sh release
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

## 上游与许可证

ZIME 基于 [Linnet](https://github.com/Ares-X/Linnet) 的
`9334c4ac563b0dad341c3661c59a4e4467b01e36` 修改，并间接使用 Squirrel、
librime、万象、RIME-LMDG、rime-ice 和 HallelujahIM。修改后的组合源码按
[GPL-3.0-or-later](LICENSE.txt) 发布；数据与第三方代码的精确来源和许可证见
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) 与 `LICENSES/`。
