# ZIME 开发指南

当前用户功能见 [README](../README.md)，贡献约定见 [CONTRIBUTING](../CONTRIBUTING.md)，
附件生成与发布见 [发布指南](release.md)。[继承的 Linnet 开发说明](legacy/linnet-development.md)
仅作历史参考，其中自动更新、云同步和中文方案选择不代表当前 ZIME 功能。

## 构建

支持 Apple Silicon、macOS 13+，需要完整 Xcode、Ruby、C++ 工具链及 ripgrep。
按锁文件准备依赖后构建：

```sh
git submodule update --init --recursive
./action-install.sh
no_download=1 ./action-build.sh release
```

默认产物是隔离身份的 local-build，不会覆盖已安装输入法。
禁止直接修改生成的 `build/`、`data/plum/`、`lib/` 来修复源码问题。

## 当前架构

- `sources/SquirrelInputController*`：InputMethodKit 会话、键盘入口与候选展示。
  双语快捷键由 `SquirrelInputController+Bilingual.swift` 统一处理；测试直接编译这些生产方法。
- `plugins/smart_english/`：英文补全、混输、纠错和学习。普通中文选词由 Rime 负责。
  中文模式内中文、英文和 Emoji 共同学习；独立英文模式另行训练。
- `sources/ZIMELocalLexicon.swift`：只读本地译文索引、词义/注释/引用解析和有限缓存。
- `sources/ZIMECandidateTranslator.swift`：本地优先注释、当前页缺词请求、取消及缓存。
  `ZIMETranslationProvider.swift` 是唯一在线翻译/凭据边界，默认关闭；
  在异步等待前后检查当前服务与授权，不从剪贴板或文档收集内容。
- `sources/LinnetSettings/`：外观、输入、翻译、词典、本地数据五个设置页。
  外观的即时投影与其他草稿的应用/撤销分开，所有个人数据操作保留原有并发及备份边界。
- `LinnetDataRegistry*`：不可变 Data/Runtime 的校验、历史状态读取与恢复。
  停用的上游在线更新生产者不进入应用。`tests/fixtures/Legacy*` 仅构造历史输入，
  用于验证兼容读取、备份格式和中断事务恢复，不能当作当前功能或产品覆盖率。
- `ZIMEInstallTransaction.swift` 与 `tools/ZIMEInstallHelper.swift`：
  当前 ZIP/PKG 共用的安装事务；生产入口是 `tools/ZIMEInstallMain.swift`。
  升级保留注册 App 目录 inode、UserData 和回滚材料。

ZIME 默认提供全拼和智能英文；简体/繁体是两个 macOS 输入源，共享设置与学习。
兼容的其他拼音方案只在隔离回归环境中验证，不加入默认输入模式列表。
设置版本区只读本机安装身份，并链接 ZIME Releases，不查询上游 Linnet Catalog。

## 验证

```sh
swiftlint lint --strict --config .swiftlint.yml
./scripts/run_periphery.sh
./tests/verify_development.sh core
./tests/verify_development.sh app
./tests/verify_zime_coverage.sh
```

- `quick` 是日常快速反馈；`full` 是 `core` 的易读别名；`release` 统一全量、App、
  lint/Periphery/覆盖率。范围、缓存和门槛见 [测试分层](testing.md)。
- `core`：Swift、候选/外观、翻译、Host 提交、发布/CI 契约、安装事务、隐私、
  英文投影、默认原生回归和六项专项（数字混输已在默认矩阵中）。
  `all` 是 core 范围加 App 检查，不包含 lint/Periphery。
- `app`：最新 local-build 的身份、资源、依赖、数据隔离和构建新鲜度；
  不等于完成设置 UI 点击测试。
- Periphery 索引实际 Host、Settings、安装助手、pack tool、runtime inspector、
  input-source inspector 和英文数据生成器；不通过忽略清单隐藏未使用代码。
- 覆盖率只统计指定 Swift 模块及生产依赖；不是全项目或分支覆盖率。
- `verify_zime_source_boundaries.rb` 防止退役网络入口和测试夹具进入应用，
  含负向自测；不代替编译与行为测试。
- 真实设置点击需要独立测试桌面/CI，不能在日常桌面伪造隔离标志。
  真实 API 必须单独获得网络与凭据访问授权，离线 Mock 测试不能计作真实 API PASS。

测试临时根目录由 runner 创建并清理。默认原生套件与专项参数见
`./tests/verify_rime_runtime.sh --list-probes`；单个 probe 不代表整套通过。
真实应用、双屏、跨系统与长时使用边界见 [验收清单](ZIME-ACCEPTANCE.md)。

## 修改与交付

先查看 `git status`，保护用户已有改动。先复现，再改唯一负责该行为的实现，
同时补回归。风险相关的格式、静态和行为测试都通过后才建立干净的本地提交。

本机修复默认按 [AGENTS.md](../AGENTS.md) 递增版本、构建候选并事务安装。
成功核验后只保留最近三代安装包，不清理个人数据或安装事务回滚目录。
GitHub 推送、Release 与安装不是同一操作；未经明确要求不自动推送或发布。

上游版本只由 `upstreams.lock.json` 与锁定 gitlink 决定。
维护时先检查 `scripts/upstream-sync report`，更新后执行
`scripts/upstream-sync verify`、数据投影及原生回归；不从运行时跟随上游更新。
