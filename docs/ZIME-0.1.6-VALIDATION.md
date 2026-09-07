# ZIME 0.1.6：中文简拼优先与学习排序

日期：2026-09-07。版本 0.1.6 / build 7，arm64，最低目标 macOS 13。

## 根因与规则

旧版智能英文过滤器把完整英文单词提升到首位时，只保护非简拼的强中文
词条，并依赖静态词频判断。`key` 可以按 `ke+y` 匹配“可以”，但这类
简拼被排除；学习后原生 Rime 已将其标记为 `user_phrase`，下游英文
提升规则仍把 `key` 放回第一位。故障复现中连续选择三次“可以”，学习
身份已经变化，首位却依然是英文；并非必须重建或清空学习词库。

本版调整同一输入范围内的小写中英冲突排序：

- 中文模式保护常见完整拼音词及简拼词，也独立保护原生 `user_phrase`。
  已学中文不再因系统词频低而被固定英文规则压住。
- 只有常见完整英文在中文匹配较弱时才优先，例如无个人学习记录时的
  `hello`、`what`、`apple`、`banana`、`computer`、`cloud`、`interface`、`email`。
- 中文之间的偏好仍由原生 Rime 学习决定，不新增旁路偏好数据库，不对
  `key` 或“可以”做特判。英文候选仍可选。
- 显式首字母大写／全大写及独立英文模式沿用英文意图；不修改翻译展示、
  上屏边界、候选框外观或翻页操作。

判断采用现有本地词库的频率启发式，并非语义识别：Rime 权重为
`log(raw / 1e8)`，普通中文沿用 raw ≥ 100，新增简拼门槛 raw ≥ 1,000，
常见英文门槛 raw ≥ 1,000,000。简拼更高的门槛避免 `cloud → 查漏洞`
这种冷门偶合压过英文；主动学习的中文不受这些静态频率门槛限制。

## 验证

所有学习测试均使用临时独立用户目录，没有向实际用户学习库写入测试词。

- `tests/verify_rime_runtime.sh --zime-bilingual-probe` 通过：
  - 无学习记录时 `key` 首选“可以”；常见英文弱中文例外保留。
  - `the`、`agent`、`can`、`she`、`you` 有可靠中文匹配时中文优先。
  - 选择三次“可以”后保持首位，候选类型为 `user_phrase`。
  - 主动选择低频 `what → 我好爱他` 后，该中文超过英文，并可持久化。
  - 销毁引擎并重新初始化，以及启动全新测试进程后，以上偏好仍存在，
    英文仍可选。之后选择六次“科研”，`key` 首位成为“科研”，证明不是
    固定“可以”捷径。测试次数是夹具条件，不承诺所有用户库同样次数生效。
  - 独立英文模式及 `Key` / `KEY` / `What` / `WHAT` 不受影响。
  - 保留全拼、首字母、错序匹配，并验证“学习CS急停”“了解AI技术”
    “使用CPU性能”进入前九候选且仅提交选中的主文本。
- `tests/verify_rime_runtime.sh --zime-paging-probe` 通过，包含分页边界。
- `tests/verify_zime_translation.sh` 通过：124,988 条源记录身份校验、
  本地释义与译文边界测试通过；API 仅用 mock，没有读取凭证或请求真实服务。
- Release App 构建成功，最终 ZIP/PKG 打包校验成功；签名 App 和已安装
  App 均通过 `tests/verify_zime.sh` 与深度严格签名校验。
- 测试插件按 Xcode 相同规则 strip 后，与最终构建插件逐个比较除
  `__LINKEDIT` 外的 Mach-O 段，内容一致；安装后的主程序和插件与最终
  签名 App 字节一致。

验证范围限制：尝试旧 `--mixed-input-probe` 八方案大矩阵时，在历史
自然码方案 `linnet_zh` 的 `xierwanasi → 希尔瓦娜斯` 补充词典检查遇到
空候选，未继续完成该矩阵，不计为通过。ZIME 当前启用的是全拼
`linnet_zh_pinyin` 和英文 `linnet_en`；本版以这两个实际产品方案的原生
回归为交付依据，未修改旧方案来绕过该失败。未重跑整套 Swift/UI 测试，
也未将原生引擎夹具或安装状态检查称为用户前台人工敲字验收。

## 本机交付

已安装 0.1.6 / build 7，进程从
`/Users/zga/Library/Input Methods/ZIME.app/Contents/MacOS/ZIME` 启动。
Hans 输入源状态为 `registered:selected-observation:selectable:path-unknown`，
实际程序位置另由进程路径验证。仅替换 App，未部署或重建用户词库。

- 设置 schema 保持 14；安装前后文件 SHA-256 完全一致：
  `125d18d3d9f2953e230866ce6ac6877c1790d9410632c5b90a9d084cd7aa3b5b`。
- 保留已有的 16pt 字号、每页 5 个候选、双语竖排、雾灰、整行选中和圆角。
- 旧 App 备份：`/Users/zga/Library/Input Methods/.zime-core-update.cCBe6J/previous.app`。
- 开发预览仍为 Ad-hoc App 签名，PKG 未使用 Developer ID 签名或公证。

| 文件（arm64） | 字节数 | SHA-256 |
| --- | ---: | --- |
| `ZIME-0.1.6-arm64.pkg` | 502,332,508 | `270bf3fddc1f4e97d2b2b142915fe41bb6b1758f0824240c0a0441c4f6353454` |
| `ZIME-0.1.6-arm64.zip` | 502,346,551 | `08134ef38382bfbe15dd77680b9ebff9cd741aee100d5ef1c62611af53163dd2` |

交付目录：`/Volumes/Seagate ZP1000/Dev/ZIME-0.1.6-arm64/delivery/`。
