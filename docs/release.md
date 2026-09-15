# ZIME 发布与产物验证

当前 ZIME 使用 **Ad-hoc App 签名、未签名 PKG**，没有 Apple Developer ID 或公证。
不要把历史 Linnet CMS 迁移记录当作 ZIME 的授权，也不要为通过测试修改旧证书或迁移指纹。
历史流程原文保存在 [Linnet 发布归档](legacy/linnet-release.md)，不是当前操作指南。

## 本地验证

准备锁定依赖后，在有图形会话的 Apple Silicon Mac 上运行：

```sh
./action-install.sh
make release
./tests/verify_development.sh release
```

`release` 包括核心、安装事务、隐私、本地 App / Settings 隔离数据、严格质量和覆盖率门，
不安装输入法。`all` 仍保留为不含严格质量/覆盖率的兼容分组；范围见 [测试分层](testing.md)。
覆盖率报告只统计实际插桩的 Swift 模块，不是全项目百分比；报告保存在
`build/zime-coverage/run.*/`。完整点击测试另在 CI 或明确隔离的桌面运行：

```sh
./tests/verify_visible_settings_fixture.sh --ui-test
```

不要在正在使用的桌面伪造 CI / 隔离标记绕过保护，也不要把环境跳过记为 PASS。
UI 测试账户若已有 local-build 开发版偏好会拒绝运行，避免清除既有开发状态。

## 构建可验证候选

先提交本地修改，使工作树干净。输出目录必须尚不存在；以下命令只创建本地产物，不上传：

```sh
make archive ARCHIVE_OUTPUT_DIR="/absolute/path/to/new-zime-delivery"
scripts/verify-zime-delivery "/absolute/path/to/new-zime-delivery" "$(git rev-parse HEAD)"
```

ZIME 的 `archive` / `package` 已改用现行安装器；`community` 不适用于 ZIME。
不要调用旧 `release-control`、`verify_product.sh release` 或 CMS provisioning 来发布 ZIME。

候选包含完整 ZIP、当前用户 PKG、Core ZIP、锁定的 LTS 模型，以及
`manifest.json` 和 `SHA256SUMS`。验收检查：

- 产品、版本、构建号、arm64 架构、源码 revision、干净工作树和上游锁摘要；
- 模型与锁文件一致，所有附件清单、大小及 SHA-256 一致；
- App / Settings 的正式身份、输入模式、嵌套签名、词典和隐私；
- ZIP 解压前路径与链接检查，Full / Core 的 App 字节一致；
- PKG 确为未签名、仅限当前用户、暂存式安装，PKG / ZIP 内容一致；
- 使用生产安装 helper 的只读检查验证离线数据，不执行安装脚本。

输出失败不能上传；修复后使用新的输出目录重新构建。完整包替换内置 Data / Runtime，
Core 只更新 App；两者均应保留 UserData、个人设置与学习记录。真实升级仍需人工验收，
不能仅从模拟事务测试或静态脚本检查推断。

## GitHub Actions 与发布

PR 和手动完整验证配置了 macOS 15 / 26 矩阵，执行 Core、App、Settings 点击、
覆盖率、SwiftLint 和 Periphery。它们是 GitHub 当前的标准 Apple Silicon runner，
但不能替代 macOS 13 / 14 的兼容性实机验证。
参见 [GitHub runner 文档](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)。

手动 `ZIME release verification` 验证指定源码后生成候选附件，保留三天。
工作流只申请 contents: read，不导入旧 CMS 密钥、不创建标签、不写 Draft 或正式 Release。
静态工作流检查通过，不等于远端工作流已经运行成功。

发布前需完成 [真实验收清单](ZIME-ACCEPTANCE.md)，使用同一候选原字节核对版本、摘要和更新日志。
只有维护者明确要求发布时才上传；先上传所有附件到 Draft，下载核对清单和摘要，
确认源码标签与候选 revision 一致后再公开。任何失败都不能记为已发布。

用户首次信任使用 macOS 的标准 Finder / 隐私与安全性流程。不得关闭 Gatekeeper、
清除隔离属性或修改系统安全策略来取得测试通过。
