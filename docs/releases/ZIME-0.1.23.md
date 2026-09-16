# ZIME 0.1.23 — 词库与离线释义更新

2026-09-16，build 32。Apple Silicon、macOS 13+ 开发预览。

## 更新

- 万象 Base 词库升级至 **v17.10.3**；保留 ZIME 的学习排序、混输、读音修正及八套全拼/双拼键位投影，不整体导入上游界面和脚本。
- 更新 **2026-09-15 万象简体 LTS 模型**。固定原始附件身份及 SHA-256，并随本版本镜像分发，避免上游同名 LTS 附件替换影响后续构建。
- **CC-CEDICT 更新至 2026-09-15**，含 125,067 条源词条。与旧快照相比，新增 114 个词头/读音组合、移除 35 个旧组合、修订 94 条释义；继续区分译义、注释和引用，保留完整原文。
- Hallelujah 英文释义、雾凇补充词库、输入快捷键和云翻译规则保持不变。

## 下载与升级

| 安装包 | 用途 |
| --- | --- |
| [完整 ZIP](https://github.com/zgat/ZIME/releases/download/v0.1.23/ZIME-0.1.23-arm64.zip) | **本次升级推荐**：包含全部新词库、模型和程序 |
| [完整 PKG](https://github.com/zgat/ZIME/releases/download/v0.1.23/ZIME-0.1.23-arm64.pkg) | 同一套完整内容，通过 macOS 安装器安装 |
| [Core ZIP](https://github.com/zgat/ZIME/releases/download/v0.1.23/ZIME-0.1.23-arm64-core.zip) | 只更新程序与随附 CC-CEDICT，保留旧万象词库和模型 |

无需先卸载。完整包替换内置 Data/Runtime，但保留个人词频、学习记录、自定义词和设置，
并创建回滚备份。Core 需要已有 0.1.17 或更新的兼容完整数据。
安装前保存输入内容并关闭 ZIME 设置，详见 [安装说明](https://github.com/zgat/ZIME/blob/main/docs/ZIME-INSTALL.md)。

附件另有 `SHA256SUMS`、`manifest.json` 和锁定模型镜像。
模型文件及 GitHub 自动生成的 Source code 归档不是安装器。

## 已知限制

- App 为 Ad-hoc 签名、PKG 未签名，均未经过 Apple 公证，未开启自动更新。
- 未将自动化回归等同于真实在线 API、跨系统/应用、双屏或长期使用验收。
- Settings 通用与翻译草稿同时应用的组合流程仍待补测；此前发现的待提交路径未在本次数据更新中修复。请分别修改并应用，留意保存状态。

ZIME 源码为 GPL-3.0-or-later；CC-CEDICT 及其索引为 CC-BY-SA-4.0，
万象词库和模型为 CC-BY-4.0。完整归属见仓库及安装包内许可证。
