# 验证记录索引

README 描述当前产品；这里保留各版本的历史验证范围和实现边界。
历史文档中的按键、界面和安装状态仅适用于记录时的版本，当前行为以 README 和最新版本说明为准。

| 版本 | 验证主题 |
| --- | --- |
| 0.1.21 | [空格选择高亮候选](ZIME-SPACE-SELECTION-2026-09-14.md) |
| 0.1.20 | [换位纠错与候选学习](ZIME-TRANSPOSITION-2026-09-10.md) |
| 0.1.19 | [未匹配尾串的完整混输候选](ZIME-LITERAL-MIXED-2026-09-10.md) |
| 0.1.18 | [英文补全与混合组句边界](ZIME-CANDIDATE-BOUNDARIES-2026-09-10.md) |
| 0.1.17 | [上游、离线数据与安装事务](ZIME-0.1.17-VALIDATION.md) |
| 0.1.14–0.1.16 | [版本说明](releases/ZIME-0.1.16.md)、[翻译来源与无损解析](ZIME-TRANSLATION-SOURCES-2026-09-08.md) |
| 0.1.13 | [数字选词与 Enter 原文提交](ZIME-0.1.13-VALIDATION.md) |
| 0.1.12 | [字母数字组合](ZIME-0.1.12-VALIDATION.md) |
| 0.1.11 | [大小写释义查询](ZIME-0.1.11-VALIDATION.md) |
| 0.1.10 | [快捷键录入](ZIME-0.1.10-VALIDATION.md) |
| 0.1.9 | [中英文分模式学习](ZIME-0.1.9-VALIDATION.md) |
| 0.1.8 | [英文选词学习](ZIME-0.1.8-VALIDATION.md) |
| 0.1.7 | [候选分页与设置交互](ZIME-0.1.7-VALIDATION.md) |
| 0.1.6 | [中文简拼与跨语言排序](ZIME-0.1.6-VALIDATION.md) |
| 0.1.5 | [配色、字重与独立外观选项](ZIME-0.1.5-VALIDATION.md) |
| 0.1.4 | [词条归属、去重与注释分层](ZIME-0.1.4-VALIDATION.md) |
| 0.1.3 | [地区释义与配色](ZIME-0.1.3-VALIDATION.md) |
| 0.1.2 | [翻页边界与菜单栏](ZIME-0.1.2-VALIDATION.md) |
| 0.1.1 | [词库比较、基础功能与已知限制](ZIME-0.1.1-VALIDATION.md) |

## 开发验证

当前验证体系与覆盖边界见 [完整验证跟进](ZIME-VALIDATION-FOLLOWUP-2026-09-14.md)，
真实系统/应用/服务验收见 [验收清单](ZIME-ACCEPTANCE.md)。

[核心检查入口与测试修复](ZIME-TEST-GATES-2026-09-14.md) 记录当前测试分工及验收边界，
属于开发维护，不是新的产品版本。

## README 配图

配图由 `tests/LinnetCandidateWindowInteractionTests.swift` 复用当前候选窗组件生成，
使用 `data/squirrel.yaml` 的配色和 `resources/zime-cedict.sqlite3` 的中文释义。
展示词条是固定演示样例，不冒充实时引擎排序；不读取个人学习数据，也不调用在线翻译。

在 macOS 上重新生成全部配图：

```sh
bash tests/verify_candidate_window_interaction.sh \
  --readme-product-gallery data/squirrel.yaml resources/readme/input-modes.png resources/readme/bilingual-features.png \
  --readme-theme-gallery data/squirrel.yaml resources/readme/theme-gallery.png \
  --readme-regional-gallery data/squirrel.yaml resources/readme/regional-glosses.png \
  --readme-appearance-gallery data/squirrel.yaml resources/readme/appearance-controls.png
```

随后运行 `bash tests/verify_candidate_window_interaction.sh`，执行交互测试并比较仓库配图与重新渲染结果。
生成器和图片须一起更新，再人工检查文字、裁切、译义及按键描述；不要只替换图片而留下过期生成模板。
