# ZIME 0.1.17 上游更新验证

2026-09-08，macOS 26.6.2 (25G83)，Xcode 26.6 (17F113)，arm64。
版本 0.1.17 / build 18；测试使用独立数据目录，未替换当前已安装的输入法。

## 已完成的源码与运行验证

- 锁定运行库重新构建、架构/插件清单校验、App Release 编译：通过。
- `verify_zime_upstream.sh`：24 个 Unicode 边界编码互不碰撞，普通汉字编码不变；
  实际 Lua 动态库包含 5.4.9。
- `verify_chinese_source_projection.sh`：42 条已审核纠错仍精确适用；
  104,526 条补充词均为可核对读音，无猜测读音；4,165 组同音编码低优先级约束通过。
- `verify_swift_units.sh`：完整 Swift owner gate 通过，包含外观、设置、IPC 与数据协调。
- `verify_zime_translation.sh`：源词条无损保存、本地译义、模拟云传输、来源标签及 Host
  原文/译文提交通过；没有读取真实凭据或向翻译服务发送请求。
- 真实 Rime 的 bilingual / alphanumeric / case / shortcuts / paging probes：通过。
  包含 key 的双向学习、两种模式隔离、跨进程保存以及 Emoji 导出/恢复。
- `--profile-key-matrix-probe`：八套方案通过。修复测试夹具仍假设所有继承方案已默认
  部署的问题；仅该隔离夹具显式部署八套方案，产品仍只有全拼和英文默认输入方案。
- `verify_chinese_grammar.sh`：八套方案的 LTS 投影与既有 grammar-on/off golden case
  通过，测得冷启动 571 ms（该用例阈值 750 ms）。
- `verify_lua_lifetime.sh`：重复初始化/使用/结束及载入限制通过。
- 发布元数据、锁定资产校验、离线数据信任和产品交互合同：通过。

## 小样本性能与候选对比

保留 0.1.16 的运行库和数据，与新版做独立进程的 11 组 LTS 冷查询。
输入涵盖 `ni`、`nihao`、`key`、`shuai`、`feic`、`shurufa`、`abeierjiang`、
`shengchengshirengongzhineng`、两个日常整句及 `b`。11 组首候选均保持一致，
新版单次冷查询为 44–354 ms；这只是有限样本，不是整体质量或性能提升结论。

混合输入 `xuexicsjiting` 的 8,192 个测量样本：p95 2.836 ms、p99 2.988 ms。
这不包含系统输入框、图形渲染和真实应用切换延迟。

## 安装事务验证

`verify_zime_installer.sh` 使用临时目录，覆盖首次完整安装、完整升级、Core-only，
8 个发布后失败回滚边界和 4 种发布前拒绝（App、词库、退出失败、仍有进程），
验证注册 App inode、旧/新字节和学习数据保留，以及符号链接路径拒绝。
ZIP 与 PKG 的真实入口使用同一个事务和校验器，没有测试专用 HOME 重定向。

打包工具还负责解包后签名、数据布局及安装脚本一致性校验。交付文件的最终尺寸和
SHA-256 以 Release 的 `SHA256SUMS` 为准。本记录不把包级验证描述为已在所有
macOS 版本完成交互安装测试；首次授权和输入源添加仍需要系统及用户操作。

## 保持不变的边界

没有安装/重启用户正在使用的 ZIME，没有修改个人学习、设置或 API 凭据。
没有整体合入上游 UI 或 schema，没有改变主题、候选排序策略或翻译上屏语义。
未修复或扩大承诺微信截图对候选窗的覆盖能力。
预览未 Apple 公证；断电/强制结束留下的安装标记需要保留备份并检查，不能直接删掉标记继续覆盖。
