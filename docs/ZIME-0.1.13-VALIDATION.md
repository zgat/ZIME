# ZIME 0.1.13：数字选词、回车输入原文

日期：2026-09-07。版本 0.1.13 / build 14，arm64，最低目标 macOS 13。

## 更新后的按键合同

本次按用户最新体验反馈替代 0.1.10 的“回车确认当前候选”设计。

- 数字 1–9 选择当前页对应候选；Tab 仍切换原文／译文。
- 默认回车和数字键盘 Enter 提交完整待输入原文，不使用高亮候选：
  `key → key`、`nihao → nihao`、`iMe → iMe`、`x7 → x7`。
  在译文状态下回车也不提交译文，数字键才选择对应译文。
- 没有待输入内容时，回车透传给前台应用，不吞换行。零输入预测即使
  已用方向键高亮，回车或空格也只退出预测，不选中建议。
- 空格不再选择高亮候选，默认提交原文并加空格；独立英文现有的
  “附加空格”偏好继续有效。此边界已向用户说明，尚未收到相反选择。
- 鼠标与辅助功能的明确候选选择保留。已有的有效数字选词、翻页和
  字母数字原文连续输入规则不变。
- 原文提交复用 librime 现有 `CommitRawInput` 路径，保留用户已明确
  选择的前缀，其余部分按原文提交。光标位于中间时也不丢弃后半段。
  未选择的候选不因回车或空格增加学习次数。
- 智能补全仍只替换待输入内容；补全后回车提交更新后的这段原文。

设置中的动作更名为“输入原文”／`Submit original input`，内部动作改为
`commitRawInput`。schema 17 读取旧 `commitCandidate` 或旧译文确认键用于
迁移，保留录入的按键，但执行新的原文动作；保存时不再写回旧字段。
关闭智能补全的 `null` 绑定可往返保存，其他快捷键与冲突校验不变。

## 验证

- `tests/verify_rime_runtime.sh --zime-shortcuts-probe` 通过。真实引擎验证
  中文／独立英文下的 Return、keypad Enter、Host 使用的 raw API、Space，
  覆盖拼音、英文纠错、大写、缩写、混合数字及高亮非首项后的原文提交。
- 数字 1–9 逐项选择结果正确；原文提交前后对比候选学习次数不变；
  中间光标不截断原文；全拼 `xiazhouni` 明确选择“下周”前缀后，回车
  得到 `下周ni`；空闲按键、已导航预测和关闭英文附加空格的测试通过。
- `--zime-bilingual-probe`、`--zime-case-probe`、`--zime-alphanumeric-probe`
  及 `--zime-paging-probe` 全部通过。大小写仍覆盖 1,064 个词头的
  4,255 种变体，中文混排／独立英文学习隔离不变。
- 完整 `tests/verify_swift_units.sh` 通过，包括旧配置迁移、新配置往返、
  快捷键原生录入、候选窗口交互和设置事务测试。
- `tests/verify_zime_translation.sh`、Release 构建、产品标识和设置清理
  检查通过。新增 `verify_zime_commit_contract.sh` 检查 Host 原文分支
  清除译文覆盖、取消旧翻译任务并只走原文退出，不调用候选选择。
- ZIP/PKG 打包、内部解包以及最终 ZIP 独立解出的 App 严格深度签名
  校验通过，产品标识复检确认版本 0.1.13 / build 14。

验证边界：Host 路由检查是源码合同，不冒充前台 IMK 自动输入；本轮未
运行完整 XCUITest。旧 Linnet 原生总门禁仍受“八种中文方案”遗留断言
限制，使用以上 ZIME 专项，不宣称旧总门禁通过。问题 6 的副屏截图现象
仍待截图工具与取消后行为信息，本版未修改候选框窗口层级或隐藏逻辑。

## 安装状态

当前本机仍为 0.1.10，ZIME Settings 进程 98338 仍在运行。本轮未强制
关闭窗口、替换输入法或清理学习。等待用户保存并关闭设置后，可用
`scripts/update-zime-app` 作 Core-only 更新；本版包含 0.1.11 的通用
大小写翻译和 0.1.12 的字母数字混合输入修复，无需逐版安装。

真实设置 SHA-256 保持不变：
`125d18d3d9f2953e230866ce6ac6877c1790d9410632c5b90a9d084cd7aa3b5b`。

交付目录：`/Volumes/Seagate ZP1000/Dev/ZIME-0.1.13-arm64/delivery/`。
待安装 App：
`/Volumes/Seagate ZP1000/Dev/ZIME-0.1.13-arm64/final-app/ZIME-0.1.13-arm64/ZIME.app`。

| 文件（arm64） | 字节数 | SHA-256 |
| --- | ---: | --- |
| `ZIME-0.1.13-arm64.pkg` | 502,389,287 | `a01fb890622bcdefbabaa67fdd10f1c9f932393a0534df040a6e0ef5e9066fde` |
| `ZIME-0.1.13-arm64.zip` | 502,403,786 | `8eb647d4e3a77c662f032a2e2c1d168c17aa11dfeb50ca88f276e593208da923` |

开发预览使用 Ad-hoc App 签名，PKG 未使用 Developer ID 签名或公证。
