# 2026-09-15 测试体系整理与本机交付记录

本次不改变输入行为，仅整理测试体系；版本保持 **0.1.22**，构建号 **24**。
回归完成后将同一份代码提交为 `ebcc634a2246e7efc119971859d5d019306fa0d5`，
安装候选来自该干净提交。未推送 GitHub、创建标签或发布 Release。

## 改动

- 隔离历史 CMS、旧下载器、iCloud、旧产品/安装器的失效检查，旧入口明确返回
  `ARCHIVED` 和退出码 64；有效 ZIME 发布/CI 入口保留，历史兼容数据夹具不删除。
- 增加 `quick` / `full` / `release` 分层；保留原分组。完整原生入口移除重复的
  数字混输专项调用，默认矩阵继续覆盖该行为，定向参数仍可用。
- 只缓存 Settings 投影和 C++ harness 编译产物。每个测试仍执行，独立创建用户数据。
  缓存包含多源文件传递依赖、链接库及完整性验证，缺失输入不会运行旧程序。
- Host 测试直接编译完整双语 extension；会话选词和翻页按 Swift 语法提取。
  补充取消、失效会话、失败选词、Tab 重复、智能补全和翻页边界断言。
- 五个核心模块增加行/函数覆盖率及已覆盖函数数量下限，测量范围变化或数据损坏拒绝通过。

## 已完成验证

环境：Apple Silicon、Xcode 26.6（17F113）、Swift 6.3.3。

- `verify_development.sh quick`：PASS，约 31 秒。
- `make release` + `verify_development.sh release`：PASS；后者约 973 秒，包含
  完整 Swift、词库投影、原生回归、App、严格 SwiftLint、Periphery 和覆盖率门。
- 8 套方案各 222 个对照用例通过；错误映射负向用例被拒绝。
- 原生 runtime 共执行 7 次；C++ harness 和 Settings 投影各命中缓存 6 次。
  后续 C++ 编译阶段低于 1 秒，投影阶段约 2 秒；不据此推算跨机器总体提速比例。
- 覆盖率门的 11 个负向用例通过。实际测量仍为 13 个生产文件及依赖，
  行覆盖 1444/4439（32.53%），函数覆盖 244/683（35.72%）；五模块门槛全部通过。
  这不是全项目或分支覆盖率，范围与门槛见 [测试分层](testing.md)。
- `git diff --check` 和修改的 Shell/Ruby 语法检查通过。

本机日志：`build/testing-refactor-20260915/`；覆盖率：`build/zime-coverage/run.Bj4dDL/`。
回归在提交前执行，覆盖率文件如实保留当时旧 HEAD 和 dirty 状态，不伪造干净来源。

## 安装与保留

`make archive` 生成 Full ZIP、Core ZIP、PKG、LTS 模型、manifest 和 SHA256SUMS，
并通过来源、摘要、Ad-hoc 签名、Full/Core/PKG 一致性及离线运行时校验。
产物位于 `build/zime-0.1.22-build24-delivery-20260915/`。

使用 Core 包自带事务助手升级 build 23 → 24；正式 App 签名、插件、来源和版本通过校验，
进程已重启且未隐藏。简体输入源仍选中，繁体保持已注册但未启用。
App 目录 inode、Data、Runtime/Active 和偏好文件摘要与安装前一致；安装器在静止期
验证 UserData 不变，并保留回滚备份。重启后的数据库日志轮转不等于学习记录丢失。

安装材料仍只有 0.1.20、0.1.21、0.1.22 三个版本；同版本多个构建属于同一版本代。
本次没有删除安装材料、用户数据、回滚备份或测试日志。

独立桌面真实 Settings 点击、真实 API、其他系统/应用、双屏截图及长时使用仍为
**NOT_EXERCISED**；本次也没有运行远端 GitHub Actions。见 [真实验收清单](ZIME-ACCEPTANCE.md)。
