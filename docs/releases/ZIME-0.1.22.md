# ZIME 0.1.22 — 设置清理与测试可靠性

2026-09-16，build 31。Apple Silicon、macOS 13+ 开发预览。

## 更新

- 精简设置启动，移除退役的上游自动更新、iCloud 控件和候选展开预览；保留本地备份、导入及恢复。
- 加固翻译设置保存异常时的凭据恢复，恢复未完成时不将撤销误报为成功。
- 修复测试取消后的嵌套进程残留、编译缓存错误复用和不安全输出；补齐安装检查、App 新鲜度、覆盖率来源及 CI job 级失败检查。
- 新增安装过程中 Host 重启的发布/回滚边界测试，精简重复回归；不改变选词规则、词库或 LTS 模型。

## 下载

| 安装包 | 用途 |
| --- | --- |
| [完整 ZIP](https://github.com/zgat/ZIME/releases/download/v0.1.22/ZIME-0.1.22-arm64.zip) | 首次安装，含程序、离线词库和模型 |
| [完整 PKG](https://github.com/zgat/ZIME/releases/download/v0.1.22/ZIME-0.1.22-arm64.pkg) | 同一套完整内容，通过 macOS 安装器安装 |
| [Core ZIP](https://github.com/zgat/ZIME/releases/download/v0.1.22/ZIME-0.1.22-arm64-core.zip) | 已有 0.1.17 或更新兼容完整数据时，只更新程序及随附资源 |

两种升级均保留个人词频、学习记录和设置，并创建回滚备份。Core 保留已有语言数据，
完整包会替换内置 Data/Runtime。安装前保存输入内容并关闭 ZIME 设置。
[最新安装说明](https://github.com/zgat/ZIME/blob/main/docs/ZIME-INSTALL.md)。

附件同时提供 `SHA256SUMS`、`manifest.json` 和源码构建用的锁定模型镜像；
模型文件及 GitHub 自动生成的 Source code 归档不是安装器。

## 验证与限制

发布使用已完成本机安装验证的 build 31 原始产物，源码与标签绑定
`752140e283901752d3f59453427ec76b2152765d`；后续 main 提交仅补充交付与发布文档。
完整本地 release 回归通过，包含 1,776 条 golden、64 个会话共 4,096 轮压力、
Swift/Host/离线 HTTP、安装事务、SwiftLint、Periphery 和限定模块覆盖率。
[详细验证记录](https://github.com/zgat/ZIME/blob/main/docs/ZIME-TEST-HARDENING-2026-09-16.md)。

- App 为 Ad-hoc 签名，PKG 未签名，均未经过 Apple 公证，未启用自动更新。
- 未完成真实 API、隔离桌面 Settings 点击、跨系统/应用、双屏及长期使用验收；不将本地 PASS 描述为这些场景或远端 CI 已通过。
- Settings 通用与翻译草稿同时应用的组合流程仍待补测；源码审查发现翻译草稿可能保留为待提交状态的路径，复现与修复暂缓。请分别修改并应用，留意保存状态。

ZIME 源码为 GPL-3.0-or-later；数据与第三方组件归属见仓库的
`THIRD_PARTY_NOTICES.md`、`upstreams.lock.json` 和 App 内 `ZIMERelease/LICENSES`。
