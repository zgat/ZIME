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

提交前至少运行与改动相关的检查。完整的核心检查为：

```sh
./tests/verify_swift_units.sh
./tests/verify_rime_runtime.sh --zime-bilingual-probe
./tests/verify_english_data_projection.sh
./tests/verify_zime.sh
```

如果某项检查因环境限制无法运行，请在 Pull Request 中说明原因和已经完成的验证。

## Pull Request

- 一个 Pull Request 聚焦一个主题，并说明用户可见行为的变化。
- 新增或修复输入行为时，请补充自动化测试或可复现步骤。
- 修改依赖、词库或模型时，请同步更新锁文件、来源、校验和及第三方许可证信息。
- 保持输入和候选处理的本地优先边界；任何联网能力都必须是显式、可关闭且经过单独
  隐私审查的功能。
