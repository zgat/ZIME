# ZIME 0.1.10：可录入的候选快捷键

日期：2026-09-07。版本 0.1.10 / build 11，arm64，最低目标 macOS 13。

## 使用方式与兼容

设置 → 输入 → 候选快捷键。三项都是点击后直接按键录入，不再使用下拉框。

| 动作 | 默认键 | 行为 |
| --- | --- | --- |
| 切换原文／译文 | Tab | 只切换候选状态，不上屏 |
| 选择当前候选上屏 | Enter（兼容数字键盘 Enter） | 原文、译文共用当前高亮候选确认逻辑；原文状态不会把拼音当作候选上屏 |
| 智能补全 | Option-Tab | 将选中的英文补全或纠错结果填入待输入内容，确认后才上屏；可取消绑定 |

移除旧的“Commit translation”“Translation side”和“Tab key”下拉设置，
快捷键移到独立的全局候选设置区，不属于仅英文选项。数字 1–9 仍可选词。
译文状态下未绑定的 Enter/空格不会落到隐藏原文的提交分支。

录入仅由设置窗口中的原生 NSButton 接收按键，不使用全局监听或辅助功能权限。
Esc 取消，Delete 可清空智能补全；失去焦点停止录入。拒绝重复绑定、裸字母／
数字、编辑键与常见系统保留组合；Return 和数字键盘 Enter 视为同一绑定。

设置 schema 16 迁移旧的切换／确认选择。旧智能补全获得独立 Option-Tab，
旧 pass/navigate 不强制启用补全。新格式不再写回三个旧字段。快捷键变更走
配置发布路径，不能被误判为仅外观变更；冲突配置不能持久化。
Core 在两个方案中将旧原生 Tab 行为投影为 pass，快捷键由 Host 统一处理。
修改键组合被 Host 接收后，通知原生引擎结束挂起的修饰键单击状态，防止松开
Shift 时误切换模式或上屏。普通 Shift 单击仍保留原来的模式切换功能。

补全只修改纯英文待输入内容，排除 URL、代码、中文和多行文本；处理分词后
的短语前缀，反复补全不会把 `early access` 缩成 `access`。本次未改学习排序
策略、用户库归属、翻译 API 或云端隐私边界。

## 验证

- `tests/verify_swift_units.sh` 全部通过，包含完整外观测试及新增的原生
  快捷键录入测试：Tab、Enter、数字键盘 Enter、Control-Option-K、F3、
  Esc 取消、Delete 清空、失焦停止、冲突拒绝、迁移与编码往返、补全前缀。
  录入测试使用屏幕外非激活 NSPanel，不向前台应用注入输入。
- `tests/verify_rime_runtime.sh --zime-shortcuts-probe` 通过：真实引擎两个
  方案的 Tab 均不再补全／导航；Shift、Control、Option、Command 组合结束
  后均不误切换／上屏；`cluod → cloud`、`ear → early access` 只改待输入
  内容，显式选择后才提交完整结果；中文选择得到 `你好` 而不是 `nihao`。
- `--zime-bilingual-probe` 通过，保留双向混排及模式隔离：新进程中的
  中文模式 `key=13 / 科研=10`，独立英文 `key=20`，互不训练。
- `--zime-paging-probe`、`tests/verify_zime_translation.sh`、
  `tests/verify_zime_settings_cleanup.sh` 均通过；翻译只使用本地数据和
  mock transport，没有访问凭证或发送真实 API 请求。
- Release 构建、ZIP/PKG 打包、解包签名与最终 App 产品校验均通过。

验证限制：额外执行不带参数的 `tests/verify_rime_runtime.sh` 未通过，停在
继承自 Linnet 的“必须恰好有八种中文方案”断言。更新前 HEAD 已含该断言，
而更新前及本版默认配置均只发布 ZIME 全拼和独立英文；本次未扩大范围修改
整套旧多方案测试。上述专项通过不代表完整原生总门禁通过，也不代表完成
所有前台应用的 XCUITest／人工输入验收。设置 UI 的 XCUITest 断言已更新，
未在用户当前桌面执行该套前台测试。

## 本机交付

已安装 0.1.10 / build 11，Host PID 97487 从
`/Users/zga/Library/Input Methods/ZIME.app/Contents/MacOS/ZIME` 启动。
Hans 输入源为 `registered:selected-observation:selectable:path-unknown`，
实际路径由进程另行确认。Host、Settings、智能英文插件与最终签名 App
逐字节一致。

实际生效的 `Build/linnet_zh_pinyin.schema.yaml` 和 `Build/linnet_en.schema.yaml`
均为 `tab_behavior: pass`；前者仍使用 `linnet_zh_english`，后者为 `linnet_en`。
真实旧设置保留原始 schema 14 字节，加载时迁移；其 Tab／Enter／smart_complete
组合对应本版 Tab／Enter／Option-Tab。更新前后设置 SHA-256 均为：
`125d18d3d9f2953e230866ce6ac6877c1790d9410632c5b90a9d084cd7aa3b5b`。

本次仅更新 App，没有清除或替换真实词库、学习记录与设置。可恢复的旧 App：
`/Users/zga/Library/Input Methods/.zime-core-update.MtTyTP/previous.app`。

| 文件（arm64） | 字节数 | SHA-256 |
| --- | ---: | --- |
| `ZIME-0.1.10-arm64.pkg` | 502,364,263 | `b46b12149c038957fda7f19e777b4353c0fdb890cc14dd346e4b712140c14b84` |
| `ZIME-0.1.10-arm64.zip` | 502,377,024 | `5e839be8c10465b04a231486dc7a0c94a2534ca6d6ae87a033e5fc5fc5c034be` |

目录：`/Volumes/Seagate ZP1000/Dev/ZIME-0.1.10-arm64/delivery/`。
开发预览为 Ad-hoc 签名，PKG 未使用 Developer ID 签名或公证。
