# 2026-09-15 测试运行边界

目标为 0.1.22 build 29，不改变产品交互、词库或设置。

## 复现与修复

- 在私有入口夹具中让 git 枚举返回 47，原 App 门仍执行全部叶子并返回 0。
  已改为先收集完整清单，显式传播生产者错误，再检查新鲜度；增加 git/find/sort
  的部分输出后失败、空清单、较新/删除/符号链接源码和正常清单检查。
- 原 Swift scratch 自检在子程序返回后才向自己发信号。真实运行中给 shell 发 TERM，
  它等待有限寿命的子程序约 1.22 秒自然结束，没有转发取消。
- 复用 TestProcess 的进程组、单调时钟和回收逻辑，为独立测试增加继承标准 IO 的
  运行模式及取消观察。Shell 后台启动运行器并 wait，使运行中信号可被立即处理，
  运行器终止实际测试及同组后代后才允许 shell 的 EXIT 清理删除夹具。
- 标准日志直接传给调用者，不先攒在内存中；输出消费者阻塞时仍可超时退出。
  末尾诊断采用非阻塞写，避免终止阶段又卡在满管道上。
- 系统 Ruby 2.6 的真实空格路径夹具发现单字符串 spawn 会按命令语法拆分。
  改为显式 executable/argv0；SIP 会移除的测试动态库路径通过限定变量转交实际子程序。
- 接入 Swift、翻译、Host、安装事务、候选外观、覆盖率、Settings fixture、IPC 对端、
  Rime 原生矩阵、语法、学习及 Lua 探针。Rime 的 tee 管道作为一个进程组执行，
  字典工具使用 spawn 工作目录而非额外的外层子 shell。

## 验证状态

运行器及入口自检在 Homebrew Ruby 和系统 Ruby 2.6 下通过。CI 契约、原生入口
编排与所有测试脚本语法检查通过，独立 Swift 全量（含外观、数据协调和 IPC）通过。
首次全量门在原生语法前置检查处失败：接入运行器时两处依赖清单被误当成命令加上了
前缀。已修正并补充缺失路径诊断；此失败记录保留为 `full-release.log`。
提交 489a013 对应的预生成包不用于安装；修正后重新跑完整门并另生成最终包。

最终提交 `371ab0a06eb39b685efdbde9f5f8a9dd3cd57e4d` 的
`tests/verify_development.sh release` 全量通过（退出码 0），记录为
`full-release-final.log`。包含全部 Swift/外观/IPC、13 个候选翻译变异、8 方案
1,776 个 golden、默认原生矩阵与六项专项、4,096 轮会话压力、App、SwiftLint、
Periphery 及覆盖率门。SwiftLint 为 73 个文件、0 违规；没有降低覆盖率阈值。
覆盖率报告为 `build/zime-coverage/run.3sqjdl/`，记录相同源码提交及
`source_dirty: false`。系统 Ruby 2.6 的完整 Swift 缓存回归另行通过。

独立原生验证也通过：语法 A/B 冷启动 583 ms，三种学习策略及恢复、默认原生矩阵。
这些定向结果不替代最终完整门；首次失败日志不混作成功。

日志目录：`build/testing-runtime-owner-20260915/`。未推送或发布 GitHub。

## 本机交付

最终 Full/Core ZIP 与 PKG 位于 `build/zime-0.1.22-build29-final-20260915/`，
绑定上述提交。摘要、来源、Ad-hoc 签名、Full/Core/PKG 一致性和离线数据检查通过。
仍未公证，未发布 GitHub。较早 `build29-delivery` 目录的预生成包未用于安装。

通过最终 Core 包中的事务工具从 build 28 更新到 build 29。安装后 App 身份、
版本、签名、资源及隐私检查通过；唯一运行进程位于正式安装路径，未隐藏。
简体输入源可选，繁体已注册但仍未启用，不主动改变用户原有启用选择。

安装前后的 Data、Runtime/Active、偏好文件摘要及 App inode 完全一致；学习数据由
Core 更新事务保留。回滚目录为
`/Users/zga/Library/Input Methods/.zime-install-CA5586CB-AC66-4680-89C4-61AFFE419FAB`。
核验记录为 `installed-app.log`、`installed-runtime.log`、`input-source-*.log` 和
`data-before-install.json` / `data-after-install.json`。

包盘点共 35 个 ZIP/PKG，仍属于 0.1.20、0.1.21、0.1.22 三个版本，未额外删除；
源码、个人数据、测试日志和回滚材料均保留。详见 `package-retention.json`。

## 持续审查发现

交付源码冻结后，在私有副本上额外执行了运行器变异审查。基线实际执行并通过，
但 `lost-stdin`（删除 shell 的 `<&0`）及 `cancel-reported-success`（CLI 取消返回 0）
两个变异仍能完成自检并返回 0，不能宣称测试工程已没有缺口。

原因是现有二进制 IO 用例直接调用 Ruby CLI，未覆盖 shell 的后台标准输入转发；
取消用例发信号给 shell，它固定返回 130/143/129，会掩盖 CLI 自身退出码被改错。
真实原生矩阵仍验证了正常学习输入，但不能代替这两个执行层负向用例。
下一步需分别补 shell 入口的二进制输入和直接 CLI 取消用例，再检查多层调度的取消。
这属于测试判错能力不足，不是本轮已确认的输入法业务故障。

复现为日志目录中的 `audit-runtime-mutations.rb` 和 `runtime-mutation-audit.log`；
变异未修改交付源码，也未进入安装包。持续优化目标仍在进行。

## 边界

运行期保护不等于整个 shell 工作流的全阶段取消：编译缓存进程及多层脚本调度还需
继续审查信号传播。主动脱离进程组的外部服务、SIGKILL、断电不由该运行器保证清理。
真实 UI、在线服务、跨系统/应用及长时使用仍须单独验收。
