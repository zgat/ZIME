# 参与 ZIME 开发

感谢你帮助改进 ZIME。提交代码即表示你同意相应贡献按本仓库的
GPL-3.0-or-later 许可证发布。

## 开始之前

- Bug、功能建议和兼容性问题请先搜索已有 Issue；较大的行为或架构改动建议先开
  Issue 讨论。
- 不要上传个人词库、用户学习数据库、输入内容、签名证书、密钥或未经脱敏的日志。
- ZIME 当前支持 Apple Silicon 和 macOS 13 及以上版本。

## 本地开发

```sh
git submodule update --init --recursive
./action-install.sh
no_download=1 ./action-build.sh release
```

准备好依赖和数据后，提交前运行统一核心检查：

```sh
./tests/verify_development.sh core
```

此入口包含 Swift 设置／候选窗、翻译与 Host 提交、英文数据投影、静态约束、
默认原生回归，以及空格选词、双语排序、数字混输、大小写和分页专项。
兼容方案通过独立测试环境验证，不会加入默认输入模式列表。
`--zime-bilingual-probe` 只检查双语候选与学习，不代表所有输入行为均已通过。

需要检查构建出的 App 及其他开发边界时，在构建后运行 `./tests/verify_development.sh all`。
定向排查可用 `swift` / `rime` / `app` 分组；原生专项参数用
`./tests/verify_rime_runtime.sh --list-probes` 查看。
默认会删除临时测试数据；排查原生失败时可加 `LINNET_KEEP_FAILED_RIME_FIXTURE=1`
保留隔离现场，路径会随失败输出。现场可能较大，排查后请清理，不要提交到仓库。

外观与候选窗测试需要可用的 macOS 图形会话。若因环境限制跳过，请在 Pull Request
中注明原因与验证范围；`--skip-appearance-preview` 只算部分通过，不是完整验收。

## Pull Request

- 一个 Pull Request 聚焦一个主题，并说明用户可见行为的变化。
- 新增或修复输入行为时，请补充自动化测试或可复现步骤。
- 修改依赖、词库或模型时，请同步更新锁文件、来源、校验和及第三方许可证信息。
- 保持输入和候选处理的本地优先边界；任何联网能力都必须是显式、可关闭且经过单独
  隐私审查的功能。
