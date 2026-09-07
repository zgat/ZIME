# ZIME 0.1.1 验证与词库审计

日期：2026-09-07。平台：Apple Silicon / macOS，最低构建目标 macOS 13。

## 此次修正

- 候选框每一行同时显示原词与译文，旧主题缺少 `[comment]` 时也会补上。
  默认竖排，设置提供 3、4、5、6、7、8、9 的下拉选择。
- 旧设置迁移到 schema 13，保留字号、主题、候选数量和学习设置。
  仅布局迁移一次；新版本保存后的显式布局选择会被保留。
- 中文直接词典释义优先于英汉反向索引，避免“帅”被姓氏拼音覆盖。
  “帅 / 帥”首个释义为 `handsome; graceful; dashing; elegant`。
- 新增“翻译”设置页，支持 OpenAI 兼容 Chat Completions、DeepL Free/Pro、
  百度通用翻译、腾讯 TextTranslate。云翻译默认关闭，凭据使用钥匙串。
- 普通选词仍提交原文，只有显式进入译文候选状态才提交译文。
  未收录词显示“暂无本地译文”，不拼接单字释义伪造整句翻译。

## 词库比较与采用决定

| 数据 | 已核验情况 | 本次决定 |
| --- | --- | --- |
| 现有万象 / Linnet 拼音数据 | 基础源文本超过 140 万行，另有上下文模型；行数不等于独立词条数 | 保留；拼音候选数量与双语释义覆盖是两个问题 |
| 现有英汉投影 | 清单记录 147,468 个词典文本、147,718 个条目 | 保留纠错、IPA、缩写等现有行为 |
| CC-CEDICT | 2026-09-06 官方快照含 124,988 条源词条，CC BY-SA 4.0 | 已接入；生成 188,549 个中文索引头及 62,746 个完整英文短释义反向索引头 |
| ECDICT | 上游 README 描述基础 CSV 约 76 万条，仓库 MIT 许可 | 尚未接入；适合后续扩大英文覆盖，仍需检查数据来源、重复词和释义质量 |
| Rime Ice | GPL-3.0 拼音词库，现有数据已采用部分相关补充 | 不盲目叠加；它不能直接替代中英释义词典 |

来源：[CC-CEDICT 官方下载与许可](https://www.mdbg.net/chinese/dictionary?page=cc-cedict)、
[ECDICT 数据说明](https://github.com/skywind3000/ECDICT)、
[ECDICT LICENSE](https://github.com/skywind3000/ECDICT/blob/master/LICENSE)、
[Rime Ice LICENSE](https://github.com/iDvel/rime-ice/blob/main/LICENSE)。

CC-CEDICT 原始压缩文件随源码保留，转换过程可完全离线执行：

```sh
scripts/build-zime-lexicon data/zime/cedict.txt.gz /absolute/new-output.sqlite3
```

转换过滤纯引用释义，普通词义优先于姓氏和词素义，保留简繁体索引与完整短释义
反向索引。数据库及其修改继续按 CC BY-SA 4.0 分发，详见
`resources/ZIME-Lexicon-NOTICE.txt`，不会改称 GPL 数据。

SHA-256：

```text
cedict.txt.gz       70fee391949cec73eaec73476e0b6058930439cb61f435579f90209a1bb70b26
zime-cedict.sqlite3 bf439d883dceb99f0a47ac541f134a2b958e6c46fd40045579c7f1879fa5dbab
```

## 验证边界

- Release App 构建通过；候选翻译与 API 格式测试使用 warnings-as-errors 编译。
- 最终 App 已更新到本机；安装文件与解包产物逐字节一致，完整签名检查通过。
  简体输入源观察为已注册、启用且可选择；本机运行进程来自安装路径。
  运行时配置确认中英文均为 `stacked`，展开默认关闭，候选格式含 `[comment]`。
- `tests/verify_zime_translation.sh` 通过：常用词、简繁体“帅”、未知词、URL 校验、
  四家请求/响应格式、百度官方签名向量、独立核对的腾讯签名、云端关闭时不访问
  钥匙串或网络、取消与迟到响应、缓存命中及原文候选索引保持不变。
- `tests/verify_candidate_window_interaction.sh --behavior-only` 通过：逐行释义、
  3–9 项、12/16/32pt、旧主题自动补注释、无障碍选词、各主题布局和原有交互。
  退休的“仅选中词独立释义栏”测试已替换为逐行翻译合同测试。
- `tests/verify_swift_units.sh --skip-appearance-preview` 通过：包含设置迁移、
  备份、数据事务、候选框交互、示例图一致性、输入源生命周期和跨进程设置 IPC。
  唯一显式排除项为下述主题缩略图 OCR；完整默认命令仍未全绿。
- 从保留的源文件重新生成 SQLite 并逐字节比较通过，SHA-256 完全一致。
- 数据库为只读索引并有有界热缓存；10,000 次缓存查询本机约 0.003 秒。
  此数字不是整机输入延迟承诺，也不代表首次启动或云请求耗时。
- 没有使用真实 API 密钥调用任何翻译商。用户仍需在“翻译”页保存自己的凭据，
  手动点击“测试连接（发送 hello）”验证权限、服务地址、模型和额度。

目前的限制：

- 完整 Swift 测试中的主题缩略图 OCR 在 900pt 宽度误认了两个“输入”，只识别
  出 12/14 个；渲染图片人工检查为 14 个完整样例。原有缺失、空白、裁切负例
  仍通过，没有降低 OCR 的通过阈值。可显式使用 `--skip-appearance-preview`
  运行其余回归，但不能把该结果称为完整测试全绿。
- 远程原生界面控制连接不可用，未代用户完成实际应用中的最后敲字验收。
  离屏候选框测试不是实际输入客户端的端到端验收。
- 本地词典不可能覆盖任意新词和整句；云服务失败时仍可正常提交原文。
- 开发预览版采用 Ad-hoc 签名，没有 Developer ID 公证；访问钥匙串可能需要
  macOS 授权。仅更新 App 时不替换原有学习数据，并保留旧 App 供回退。

## 安装包

最终 ZIP / PKG 均经重新解包、完整签名和四类离线数据包检查。版本 0.1.1，
build 2，arm64，开发预览签名。

| 文件 | 字节数 | SHA-256 |
| --- | ---: | --- |
| `ZIME-0.1.1-arm64.pkg` | 499,882,306 | `7aaf08626e6ddaf983d46b089f8e87baecf77f5f46c5e1d7639310383d3b00e9` |
| `ZIME-0.1.1-arm64.zip` | 499,894,691 | `81bce85118eb0563a94d3de077d081db01e0cc2e54c9c456f745f28b2621a231` |
