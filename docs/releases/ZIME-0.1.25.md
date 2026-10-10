# 1 ZIME 0.1.25

2026-10-10，build 34。Apple Silicon、macOS 13+ 开发预览。

## 1.1 更新

- 修复完整拼音被英文缩写拆开组词的问题，例如 `liang` 不再产生“俩NG”。按当前布局的中文音节判断，同类输入也适用，无需删除英文缩写词库。
- 已学习的混合词、分段选词后的剩余输入和后续候选页遵循相同规则，无需清空个人学习记录。
- 保留正常中英混输，例如 `woime → 我IME`、`你好AI`；分隔符可明确边界，例如 `lia'ng → 俩NG`，中文之间的显式大写混输继续保留。
- 本次沿用 0.1.24 的万象 Base v18.1.1、2026-10-07 LTS 模型和 CC-CEDICT 释义，不更换上游数据。

## 1.2 下载与升级

| 安装包 | 用途 |
| --- | --- |
| [完整 ZIP](https://github.com/zgat/ZIME/releases/download/v0.1.25/ZIME-0.1.25-arm64.zip) | 首次安装或更新程序和全部内置数据 |
| [完整 PKG](https://github.com/zgat/ZIME/releases/download/v0.1.25/ZIME-0.1.25-arm64.pkg) | 同一套完整数据，通过 macOS 安装器安装 |
| [Core ZIP](https://github.com/zgat/ZIME/releases/download/v0.1.25/ZIME-0.1.25-arm64-core.zip) | 获取候选修复，保留已有语言词库和模型 |

无需先卸载。升级保留个人设置、词频、自定义词和学习记录，并创建回滚备份。
Core 需要已有 0.1.17 或更新的兼容完整数据。安装前保存输入内容并关闭 ZIME 设置，
详见 [安装说明](https://github.com/zgat/ZIME/blob/main/docs/ZIME-INSTALL.md)。

附件另有校验和、产物清单及锁定模型镜像；模型和 GitHub 自动生成的源码归档不是安装器。

## 1.3 验证与限制

专项回归覆盖完整音节、连续多字拼音、英文位于中文前后、分隔符、大写、已学习词条、
重启、分段选词和后续候选页；保留正常混输、补全、纠错和八套布局的原有回归。
在本机 macOS 27.0.1、Xcode 27.0 上通过完整 Release 自动化回归，包括八套布局的
1,776 项候选基线、4,096 次会话循环、安装事务、离线翻译、SwiftLint、Periphery
和指定 Swift 模块的覆盖率门。发布包另须通过完整 ZIP／PKG／Core 的一致性、签名和摘要校验。

- App 为 Ad-hoc 签名，PKG 未签名，均未经过 Apple 公证；未开启自动更新。
- 自动化测试不代替真实在线 API、跨系统／应用、双屏或长期使用验收。
- Settings 通用与翻译草稿同时应用的组合流程仍待补测；请分别修改并应用，留意保存状态。

源码为 GPL-3.0-or-later；CC-CEDICT 及其索引为 CC-BY-SA-4.0，
万象词库与模型为 CC-BY-4.0。完整归属见仓库及安装包内许可证。
