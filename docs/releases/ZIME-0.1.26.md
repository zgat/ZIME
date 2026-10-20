# 1 ZIME 0.1.26

2026-10-20，build 35。Apple Silicon、macOS 13+ 开发预览。

## 1.1 更新

- 万象简体 LTS 模型更新至 2026-10-19 快照，用于离线中文组句与候选排序；新模型可能调整部分候选顺序。
- 本次不更换万象 Base 词库、CC-CEDICT 释义或输入按键规则；保留中英混输、Shift 切换及个人学习。
- 模型来自 [万象语言数据仓库](https://github.com/amzxyz/rime-wanxiang-data/releases/tag/LTS)，在本版本中固定保存审核后的副本；上游后续替换附件不会改变本版本安装包。

## 1.2 下载与升级

| 安装包 | 用途 |
| --- | --- |
| [完整 ZIP](https://github.com/zgat/ZIME/releases/download/v0.1.26/ZIME-0.1.26-arm64.zip) | 首次安装或更新程序、全部内置数据和新 LTS 模型 |
| [完整 PKG](https://github.com/zgat/ZIME/releases/download/v0.1.26/ZIME-0.1.26-arm64.pkg) | 同一套完整数据，通过 macOS 安装器安装 |
| [Core ZIP](https://github.com/zgat/ZIME/releases/download/v0.1.26/ZIME-0.1.26-arm64-core.zip) | 只更新程序和随附资源，保留已有词库及旧模型 |

获取新 LTS 模型必须使用完整 ZIP／PKG，无需先卸载。升级保留个人设置、词频、
自定义词和学习记录，并创建回滚备份。安装前保存输入内容并关闭 ZIME 设置，
详见 [安装说明](https://github.com/zgat/ZIME/blob/main/docs/ZIME-INSTALL.md)。

Core 需要已有 0.1.17 或更新的兼容完整数据，不会升级语言模型。
附件另有校验和、产物清单及锁定模型镜像；模型和 GitHub 自动生成的源码归档不是安装器。

## 1.3 验证与限制

在本机 macOS 27.0.1、Xcode 27.0 上通过完整 Release 自动回归：包括上游迁移与
受限跳转、真实旧地址请求链、离线组句 A/B、八套布局的 1,776 项候选基线、
4,096 次会话循环、输入与学习、安装事务、SwiftLint、Periphery 和指定 Swift 模块的覆盖率门。
另对比了旧、新模型的 11 条隔离查询，首选候选保持一致；样例检查不代表通用语言质量评分。
发布包另须通过完整 ZIP／PKG／Core 的内容一致性、嵌套签名和摘要校验。

- App 为 Ad-hoc 签名，PKG 未签名，均未经过 Apple 公证；未开启自动更新。
- 自动化测试不代替真实在线 API、跨系统／应用、双屏或长期使用验收。
- Settings 通用与翻译草稿同时应用的组合流程仍待补测；请分别修改并应用，留意保存状态。

源码为 GPL-3.0-or-later；CC-CEDICT 及其索引为 CC-BY-SA-4.0，
万象词库与模型为 CC-BY-4.0。完整归属见仓库及安装包内许可证。
