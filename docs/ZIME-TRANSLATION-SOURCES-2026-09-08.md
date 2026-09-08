# 翻译来源与本地词条解析验证

本文记录的实现验证阶段未安装、重启输入法、改动用户词频/配置、读取真实密钥或发送真实翻译请求。
随后应用户请求完成安装，见 [0.1.16 安装核验](ZIME-0.1.16-VALIDATION.md)。

## 行为

- 本地可用译义优先，包括异体字/缩写引用的解析结果；已有本地译义时不访问在线服务或钥匙串。
- 在线来源显示为 `腾讯:`、`百度:`、`DeepL:`；大模型兼容接口显示 `ai:`。来源是独立元数据，切换译文候选后仍显示，但不进入上屏文字。
- 在线响应的译文字段作为一个完整候选，保留空格、括号、斜杠、分号、制表符和换行。不套用 CC-CEDICT 规则，也不按斜杠拆候选。沿用原文/译文切换和数字选词交互。
- 响应体最多 64 KiB；译文字段最多 4,096 UTF-8 字节，与 native commit 上限一致。空白、无效控制符、过大字段整体拒收，不静默截断。等待期间关闭云翻译或更换配置，会在读取密钥/发送后续请求前重新检查。
- 本地建库不再按 `CL:`、`see`、`variant of` 等前缀丢弃原始 sense。原始字形、读音、全部 senses 保留；译义、注释和引用由共享 Swift 解析器分类。
- 有直接译义时优先使用直接译义；缺少直接译义时才沿可继承的明确引用补全，匹配目标繁简字形和可选读音，并限制深度、防止循环。`used in`、`see also`、反向 `abbr. to` 不继承目标释义；缺失目标不编造译文。
- 同时含英文定义和缩写说明的旧词条保留定义；原始引用仍可在开启的悬停详情中查看。
- 括号不统一删除：已识别的用法/说明/引用移入注释，语义限定、完整语法释义、可选词形、公式及未知内容保留。地区只影响译义偏好，不能屏蔽候选自身字形。
- 建库与运行时共用 `ZIMELocalLexicon`，预生成结果供默认候选查询直接使用；缺少预生成记录时使用同一解析器回退。完整注释默认关闭。

## 数据核验

源版本：2026-09-06T07:40:00Z；输入 gzip 未改动。

| 项目 | 结果 |
| --- | --- |
| 原始词条 | 124,988 |
| 原始 sense | 199,654，逐条与 gzip 全量比对一致 |
| 已建立候选字形索引 | 197,976 |
| 可得到非空核心译义的字形 | 197,234 |
| 尚无可用核心译义的字形 | 742，不保证任何未知词都有本地翻译 |
| SQLite schema / projection revision | 3 / 3 |
| SQLite integrity check | ok |
| 文件大小 | 29,790,208 字节 |

词库 SHA-256：`4e1caa9149d212ceb411c38a52af89f8f3c3a5a456dab13b84ab9d71e872979a`

源 gzip SHA-256：`70fee391949cec73eaec73476e0b6058930439cb61f435579f90209a1bb70b26`

## 代表性结果

| 候选 | 核心译义/首译义 |
| --- | --- |
| 你、妳 | you，不混入另一个读音 nai3 的“奶” |
| 帅、帥 | handsome; graceful; dashing; elegant |
| 费城、費城 | Philadelphia, Pennsylvania |
| 世博 | World Expo |
| 上汽 | Shanghai Automotive Industry Corp. (SAIC) |
| 上证 | Shanghai Stock Exchange (SSE) |
| 瞭解 | to understand; to know about |
| 明天见 | see you tomorrow |
| 之 | possessive particle |
| `capital (city)` | 括号保留，与其他 capital 义项区分 |

未识别的注释格式保守保留，解析规则不声称能够理解任意自然语言。

## 验证范围

- `tests/verify_zime_translation.sh`：原始词条全量一致性、两次 fixture 建库确定性、拒绝覆盖、引用/循环/缺目标/读音隔离、预生成与运行时一致、括号分类、API 字段完整性、设置草稿及在线 mock、生产 Host 方法选词链路。
- `tests/LinnetCandidatePresentationTests.swift`：旧结构化注释兼容，来源字段独立传递，在线结果不拆分，分页保持来源身份。
- `tests/verify_candidate_window_interaction.sh --diagnose-only`：实际 AppKit 面板的独立 fixture；包含四种来源、多行译文、几何/可访问性、原有主题矩阵和候选交互。未重绘或比对 README 静态截图。
- `tests/verify_zime.sh`、`git diff --check`、`make release`：工程合同、补丁空白与本地构建。

在线接口使用固定 JSON 与模拟传输验证；不代表真实账号的联网、额度或服务可用性已经测试。
本地构建为 unsigned / local-build 身份，不等于生产安装包发布。
