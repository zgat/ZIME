# 2026-09-15 多层测试取消与判错能力

已验证并安装：0.1.22 build 30。仅调整测试基础设施，不改变输入法交互、设置或词库。

## 已确认的问题与修正

- build 29 后续变异审查中的两处漏检已补用例：shell 的二进制 stdin 转发与 CLI
  自身取消状态分别断言，不能再由父脚本固定的 130/143/129 掩盖错误。
- 原真实 Swift 入口在取消后仍等内部有限寿命进程自然结束：独立复现为 TERM 后
  约 3.03 秒返回，并输出 `worker finished naturally`。多层前台等待未转发信号。
- 增加统一脚本调用边界，后台登记子进程并转发取消；Ruby exec 引导先恢复信号处理，
  再建立独立进程组，避免后台 Bash 继承忽略 SIGINT。不额外创建常驻等待进程。
- 统一 development 门、Swift 子门、翻译 Host 子门及 Swift/C++ 编译缓存调用接入。
  已有叶子负责回收自己的测试进程；父级等待叶子退出后才允许 EXIT 清理。
- 启动至登记 PID 之间收到取消时，先记下请求，登记后再处理；DEBUG 夹具精确覆盖
  这个窗口。没有通过延时抽样碰运气，也没有给正式入口添加测试专用分支。
- 系统 Ruby 2.6 不支持 `-e` 内无基准路径的 `require_relative`，新编译夹具改用显式
  绝对路径加载。错误输出保留实际叶子诊断，避免线程 join 覆盖原始失败原因。

## 验证设计

两组正常回归与五个语义变异进入统一门。变异必须返回 1 并匹配对应断言；编译崩溃、
任意非零退出或无关失败不算抓到目标错误。统一入口继续验证八个 profile、默认/错误
参数、45 个 fail-fast 分支、源码新鲜度及七种编排变异。

多层回归使用实际 `verify_swift_units.sh` 和 `verify_development.sh`，仅替换第一个
昂贵叶子，分别验证运行程序/编译捕获、INT/TERM/HUP、退出状态、清理时序和进程回收。
有限寿命的模拟进程与外层独立截止时间限制测试自身失败的影响。

## 验证结果

交付源码为 `ce67aeed0e7e4d103ec41fd8a0cf6227a83dfdc1`。Homebrew Ruby 与系统
Ruby 2.6 的运行器、五项变异及统一入口自检均通过；Swift/C++ 缓存、临时目录、
原生编排与 CI 契约定向回归也通过。所有测试 shell 语法和本轮 Ruby 文件语法通过。

该提交的 `tests/verify_development.sh release` 完整执行并以 0 退出，包括：

- 45 个入口 fail-fast 分支、五个运行器语义变异和 13 个候选翻译语义变异。
- 全部 Swift、192 种外观组合、五张 README 渲染对比、双进程 Settings IPC。
- 四家服务的离线 HTTP 层、Host 提交和候选翻译边界；未访问真实凭据或发送在线请求。
- 8 方案共 1,776 条 golden、默认原生矩阵及六项专项、4,096 轮会话压力。
- App、安装事务、隐私、SwiftLint（73 个文件、0 违规）、Periphery 和限定模块覆盖率。

覆盖率报告为 `build/zime-coverage/run.iDwxUA/`，记录相同源码提交、
`source_dirty: false`。没有降低阈值、增加忽略项或把依赖文件的覆盖率当作全项目指标。
Xcode 提示本机 CoreSimulator 版本不匹配，但 macOS 构建、索引及完整门均成功；
本轮未处理与此项目无关的 iOS 模拟器安装。

日志在 `build/testing-owner-chain-20260915/`：`runner.log`、`system-ruby-runner.log`、
`runtime-mutations.log`、`system-ruby-mutations.log`、`build-release.log`、`full-release.log`。
不使用 build 29 的成功记录替代本轮结果。本轮再次复核未发现新的可复现测试工程问题，
这不代表能够保证未知缺陷不存在。

## 本机交付

Full/Core ZIP、PKG、模型及校验清单位于 `build/zime-0.1.22-build30-delivery-20260915/`。
来源、SHA256、Ad-hoc 签名、Full/Core/PKG 一致性和离线数据验证全部通过，绑定上述
源码提交。包仍为未公证预览；未推送或发布 GitHub。

使用 Core 包内的 `zime-install-helper update` 完成 build 29 → 30 事务更新。
安装后身份、版本、签名、资源、隐私与运行状态检查通过；正式路径只有一个进程，
未隐藏。简体输入源保持可选，繁体保持已注册但未启用，与安装前状态相同。

前后 Data、Runtime/Active、偏好文件摘要及 App inode 完全一致；Core 事务保留
UserData，不把运行中可能变化的学习数据作静态字节比较。回滚备份为：
`/Users/zga/Library/Input Methods/.zime-install-CC463F2A-9A29-446C-AF35-3DAE1B0EB1A3`。

交付证据为上述日志目录内的 `package.log`、`install.log`、`installed-app.log`、
`installed-runtime.log`、`input-source-*.log` 与 `data-*-install.json`。
包盘点为 38 个 ZIP/PKG，归属 0.1.20、0.1.21、0.1.22 三个版本，无需额外删除；
同版本不同 build 不另算一代。清单为 `package-retention.json`，源码、个人数据、
测试日志及事务回滚材料均保留。

## 保证边界

协作取消覆盖本工程接入的脚本所有者及测试进程组；不承诺任意外部服务主动脱离组、
SIGKILL、断电或不遵守取消协议的第三方进程都能清理。真实桌面交互、在线服务、
跨应用/双屏和长时间使用仍是独立验收范围。
