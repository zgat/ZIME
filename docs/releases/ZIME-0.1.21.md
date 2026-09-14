# ZIME 0.1.21 — 空格选择高亮候选

2026-09-14，build 22。Apple Silicon、macOS 13+ 开发预览。

## 更新

- **空格上屏当前高亮候选**：支持中文、英文、Emoji 和译文，翻页后也选择实际高亮项。
- **Enter 仍提交原始输入**，数字按位置选词；Tab 切换原文／译文。
- 中文候选与译文不额外附加空格；独立英文原文候选保留尾随空格开关。
- 分段选词保留未选尾串，正常参与学习；空闲或仅有下一词预测时，空格仍输入普通空格。

README 配图已更新，并精简为当前功能说明与简短更新公告。

## 下载

| 安装包 | 用途 |
| --- | --- |
| [完整 ZIP](https://github.com/zgat/ZIME/releases/download/v0.1.21/ZIME-0.1.21-arm64.zip) | 首次安装：App、离线词库与模型 |
| [完整 PKG](https://github.com/zgat/ZIME/releases/download/v0.1.21/ZIME-0.1.21-arm64.pkg) | 同一套完整内容，通过 macOS 安装器安装 |
| [Core ZIP](https://github.com/zgat/ZIME/releases/download/v0.1.21/ZIME-0.1.21-arm64-core.zip) | 已有兼容完整数据时，只更新程序与运行库 |

本次**没有更新上游词库或 LTS 模型**。已有 0.1.17 或更新完整数据可选择 Core，
保留现有语言数据；完整包会替换内置数据。两种方式均保留设置、个人词频和学习记录，
并创建回滚备份。安装前保存正在输入的内容、关闭 ZIME 设置。
[安装说明](https://github.com/zgat/ZIME/blob/v0.1.21/docs/ZIME-INSTALL.md)。

附件提供 `SHA256SUMS` 与记录源码提交、尺寸、哈希的 `manifest.json`。
`wanxiang-lts-zh-hans.gram` 是源码构建的锁定模型镜像，不是安装器；GitHub 的 Source code 归档也不是安装包。

## 验证与限制

通过真实 Rime 的空格／数字／Enter、3–9 行分页、混输、Emoji 学习和分段选词测试，
以及完整 Swift 设置、翻译路由与候选窗测试。本机 Core 升级后，设置与词库摘要未变，
UserData 保留、双模式与插件运行正常。
[详细验证](https://github.com/zgat/ZIME/blob/v0.1.21/docs/ZIME-SPACE-SELECTION-2026-09-14.md)。

完整 ZIP、PKG 和 Core ZIP 从同一干净源码提交构建并检查解包、签名和数据完整性。
App 仍为 **Ad-hoc 签名，PKG 未签名，均未经过 Apple 公证**，未启用自动更新。
测试不等同于所有 macOS 版本、应用及首次授权界面都已验收。

ZIME 源码为 GPL-3.0-or-later；万象字词表与 LTS 模型为 CC BY 4.0，
CC-CEDICT 改编数据为 CC BY-SA 4.0。精确归属见 `THIRD_PARTY_NOTICES.md`、
`upstreams.lock.json` 和 App 内 `ZIMERelease/LICENSES`。
