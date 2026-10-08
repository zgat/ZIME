# 1 ZIME 0.1.24

2026-10-08，build 33。Apple Silicon、macOS 13+ 开发预览。

## 1.1 更新

- **Shift 切换不再直接上屏**：输入过程中轻按左／右 Shift，切换中文与智能英文并刷新候选；保留原始输入、光标和已明确选定的原文／译文前缀。空格、数字、Enter 及按住 Shift 输入大写的规则不变。
- 万象 **Base v18.1.1** 与 **2026-10-07 简体 LTS 模型**，保留 ZIME 的八套布局、学习排序、混输和读音修正。
- **CC-CEDICT 2026-10-07**：125,215 条源词条，新增 218 个词头／读音组合、移除 70 个旧组合、修订 158 条释义。译义、注释和引用继续分层，原文完整保留。
- 更新 librime-lua；Hallelujah 英文释义、雾凇补充词库与云翻译规则不变。

## 1.2 下载与升级

| 安装包 | 用途 |
| --- | --- |
| [完整 ZIP](https://github.com/zgat/ZIME/releases/download/v0.1.24/ZIME-0.1.24-arm64.zip) | 推荐：程序、全部新词库和模型 |
| [完整 PKG](https://github.com/zgat/ZIME/releases/download/v0.1.24/ZIME-0.1.24-arm64.pkg) | 同一套完整数据，通过 macOS 安装器安装 |
| [Core ZIP](https://github.com/zgat/ZIME/releases/download/v0.1.24/ZIME-0.1.24-arm64-core.zip) | Shift 修复、程序和 CC-CEDICT；保留已有万象词库及模型 |

无需先卸载。完整升级保留个人设置、词频、自定义词和学习记录，并创建回滚备份。
Core 需要已有 0.1.17 或更新的兼容完整数据。安装前保存输入内容并关闭 ZIME 设置，
详见 [安装说明](https://github.com/zgat/ZIME/blob/main/docs/ZIME-INSTALL.md)。

附件另有校验和、产物清单及锁定模型镜像；模型和 GitHub 自动生成的源码归档不是安装器。

## 1.3 验证与限制

在本机 macOS 27.0.1、Xcode 27.0 上通过完整 Release 自动化回归，包括 1,776 项候选基线、
4,096 次会话循环、安装事务、离线翻译、代码质量及指定模块的覆盖率门。
Shift 专项覆盖左右键、双向切换、八种中文布局、光标编辑、多次切换、大小写和数字、
取消、选词及已选原文／译文前缀。安装包另须通过完整 ZIP／PKG／Core 的一致性和摘要校验后发布。

- App 为 Ad-hoc 签名，PKG 未签名，均未经过 Apple 公证；未开启自动更新。
- 自动化测试不代替真实在线 API、跨系统／应用、双屏或长期使用验收。
- Settings 通用与翻译草稿同时应用的组合流程仍待补测；此前发现的待提交路径不属于本次修复。请分别修改并应用，留意保存状态。

源码为 GPL-3.0-or-later；CC-CEDICT 及其索引为 CC-BY-SA-4.0，
万象词库与模型为 CC-BY-4.0。完整归属见仓库及安装包内许可证。
