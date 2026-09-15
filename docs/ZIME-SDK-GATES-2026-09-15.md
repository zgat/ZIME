# 2026-09-15 SDK 缓存与统一测试入口

目标为 0.1.22 build 28，不改变输入法业务行为、词库或设置。

## 修复依据

1. 私有 SDK 的头文件从 1 改成 2，旧 Swift 缓存仍 HIT 并输出 1，直接编译输出 2。
   SDK 路径、SDKSettings 和工具链版本未变，所以原环境指纹不能发现此问题。
2. 把统一入口中的候选翻译变异调用改成注释，原自检仍返回 0；脚本名文本存在不等于执行。

复查证据位于 `build/testing-boundaries-20260915/re-audit-sdk-cache.log`，及该目录的
`probe-orchestration-comment.rb`。复现只使用临时副本，未修改系统 SDK 或个人数据。

## 实现

- Swift 使用编译器 `-scan-dependencies -disable-bridging-pch` 解析真实输入，保留实际
  编译的模块名；读取桥接头的嵌套 sourceFiles、Swift 接口/预编译模块和宏依赖。
  扫描使用 whole-module 模式生成一个依赖图，实际测试编译参数保持不变；新增多文件
  冷编译、命中及辅助源码变化用例，避免只验证单文件缓存。
  不把扫描生成的 PCM/Swift 模块路径当作输入。缺依赖、扫描/编译失败均不能复用旧产物。
- 扫描文件列表不包含所有负查询，因此同时检查 SDK、工具链与头文件搜索目录的路径
  清单；目录链接去重、防环。文件内容以实际依赖为主，补充链接 stub/API notes，
  不每次哈希整个 SDK 的所有内容，也不靠 mtime 判断内容是否改变。
- SDK 回归在私有 overlay 中增删自建头文件/模块。系统 SDK 仅作为链接目标读取，
  创建前检查名称冲突；保持 SDK 路径、文件大小及 mtime 不变也不能绕过内容校验。
- 统一入口测试在私有仓库中执行未经改写的 Bash 控制流，替换叶子命令并记录参数。
  检查 8 个分组、默认及无效参数、每个 release 叶子的失败传播，以及 full 的前置步骤。
  共 42 个 fail-fast 检查和 7 个变异；旧入口字符串匹配检查从原生/发布自检移除。

## 当前验证

入口执行测试已在 Homebrew Ruby 和系统 Ruby 2.6 下通过。SDK 头文件内容、保持
大小/mtime、增删、优先级、外部 `-idirafter` 查询和缺失输入检查已通过。
`canImport` 的初版独立模块夹具未被 Swift 识别，全量门因此失败；不把该次当作通过。
改用标准 SDK 框架目录后，新增/移除模块及 `canImport` 的实际编译结果均通过。
全量门随后发现多文件扫描的单一 `-o` 冲突，已改为 whole-module 扫描并追加多文件
回归。系统 Ruby 2.6 的全部缓存用例与全部真实 Swift owner（含外观、数据协调和
双进程 IPC）已通过；完整门与安装状态待补充。

本机 SDK 头文件夹具的命中检查约 2 秒，变更重建约 4.2 秒；单独路径清单及补充摘要
约 1.35 秒；Foundation 三文件 owner 的全部输入核验实测约 2.1 秒。这是当前机器
的观察，不是跨环境性能保证。

日志：`build/testing-sdk-gates-20260915/`。本轮未推送或发布 GitHub。
真实 UI、在线服务及跨系统/应用验收不由上述隔离夹具替代。

## 后续生命周期审查

复查 `verify_swift_units.sh`、`verify_zime_translation.sh` 发现仍有直接执行测试二进制
的路径，未统一给整个可执行程序设置运行期限。编译/扫描和 TestProcess 子进程已有
边界，但它们不等于所有 Swift owner 都受保护；例如 SettingsDataCoordinatorTests
的异步 main 没有总 watchdog。当前完成运行不能证明发生死锁时也会及时退出。
下一步需补齐挂起、忽略 TERM、后代进程及信号清理的执行层反例；本批尚未修改此层，
因此不宣称持续优化目标已经完成。

已在 `build/testing-sdk-gates-20260915/bounded-owner-prototype.rb` 验证复用 TestProcess
的方案：忽略 TERM 的假测试在约 0.39 秒内以 124 退出，普通假测试的 stdout/stderr
及退出码 7 原样保留。此原型未接入正式入口，不当作运行期缺口已修复。
