# 历史测试归档，不是当前验证入口

此处保留了整理前的脚本主体（基于 `696317d`），用于追溯，不继续维护或执行。
Shell 归档主动退出 64；`tests/` 中同名入口也明确报告 `ARCHIVED`，不会虚报 PASS。
历史原始字节可从 Git 历史恢复；归档不会删除兼容数据或修改 CMS 证书、迁移指纹。

| 历史检查 | 当前验证责任 |
| --- | --- |
| `verify_product` / `verify_package_architecture` / `verify_package_lifecycle` | `verify_development.sh app`、`verify_zime_installer.sh`、`scripts/verify-zime-delivery` |
| `verify_lean_data_trust` / `verify_runtime_footprint` / `verify_retired_projection_owners` | 当前源码所有权、数据校验/恢复、隐私、原生回归；不再要求已删除的下载器/iCloud |
| `verify_input_process_offline` | `verify_zime_privacy.sh`、`verify_zime_source_boundaries.rb`：本地优先，唯一显式开启的翻译网络边界 |
| `verify_action_publication` / `verify_release_metadata` / `verify_data_channel_release` | `verify_zime_publication.rb`、`verify_zime_ci.rb`、附件验证；不采用 Linnet CMS 授权 |
| `verify_publication_owner` / `verify_release_automation` | 顶层同名入口只路由到上述当前 ZIME 检查，不再含不可达的旧分支 |
| `verify_zime_commit_contract` | `verify_zime_host_routing.sh` 的生产代码行为测试及原生按键专项；旧别名仍可调用行为测试 |

这不是“所有旧断言都移植完成”的声明：只保留当前产品职责，已停用功能的断言不再适用。
`tests/fixtures/Legacy*` **不在归档范围**：现有数据读取、备份和中断事务恢复仍需要这些输入。
上游对照/词库检查也没有删除，按 [测试分层](../../docs/testing.md) 选择。
