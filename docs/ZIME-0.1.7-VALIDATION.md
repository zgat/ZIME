# ZIME 0.1.7：设置标题点击与候选展开代码清理

日期：2026-09-07。版本 0.1.7 / build 8，arm64，最低目标 macOS 13。

## 改动

- 删除外观页的「候选浏览／仅滚动／可展开」控件及其说明、翻译字符串。
  保留中文／英文各自的横竖布局、每页 3–9 个候选和普通分页。
- 按追加要求删除功能实现，而不是隐藏开关：移除候选展开锚点与状态、
  展开／收起操作、三页／27 项迭代、多行网格和列宽计算、展开预览、
  展开状态的辅助功能入口，以及 C++ 到 Host 的一次性展开请求。
  普通翻页、按绝对索引选词、鼠标／滚轮操作和逐行译文继续使用原有路径。
- 设置 schema 升至 15，删除运行期 `CandidateBrowsingMode` 类型和字段。
  旧字段仅在解码时校验兼容值，不进入运行期或预览，编码时不再输出；
  旧 `expanded` 布局兼容读取也不恢复展开功能。没有强制重写真实用户设置。
- Local Data 的「Manual recovery & transfer」「Diagnostics」改用统一的
  SwiftUI disclosure style：标题内箭头、文字和尾部空白属于同一个原生
  Button，单击切换展开／收起；同页版本详情也遵循相同行为。按钮保留
  标准键盘／辅助功能语义并提供已展开／已收起状态。内容内的导入、恢复、
  清理等按钮和确认流程没有改动。

与候选展开无关的文字扩展器、几何外扩算法，以及 Local Data 自己的折叠
功能没有删除。历史验收记录保留，新增规则明确取代旧候选展开要求。

## 验证

- `tests/verify_swift_units.sh` 全部通过，未跳过外观测试：设置迁移、
  保存、并发操作、IPC、候选窗口与布局交互均通过。
- 新增 `LinnetSettingsDisclosureTests` 使用生产 disclosure style 和真实
  `NSHostingView`。四种中英文标题 × 两种宽度 × 箭头／文字／尾部空白
  × 展开／收起，共 48 次本地鼠标事件均通过。窗口位于屏幕外且不激活；
  没有向用户前台应用注入输入，也不加载实际设置或学习库。
- 新增 schema 9/13/14/15 的旧浏览字段读取与重新编码验证：字段不写回，
  字号、页数、配色、角形、选中效果等偏好不变；旧生成配置清理测试通过。
- 当前页快照保留绝对候选索引和最后一页边界；普通横／竖布局、3–9 候选、
  选词、翻页、悬停、候选辅助功能及主题矩阵通过。五张 README 图片与
  实际绘制结果的视觉距离均为 0，候选外观没有随清理改变。
- `tests/verify_rime_runtime.sh --zime-bilingual-probe` 通过，包含 0.1.6
  的 `key → 可以`、常见英文例外、原生学习、跨进程持久化和中英混输。
- `tests/verify_rime_runtime.sh --zime-paging-probe` 通过。删除展开请求
  不影响实际分页；第一／最后一页反复按 `-` / `+` 仍不意外上屏。
- `tests/verify_zime_translation.sh` 通过，124,988 条词典源记录身份不变；
  云 API 仅使用 mock，无凭证访问或真实请求。
- 新增 `bash tests/verify_zime_settings_cleanup.sh` 通过，防止生产代码
  恢复候选展开状态、网格、跨页迭代或开关。历史 `verify_runtime_footprint.sh`
  的相关规则已更新；未将整个历史 Linnet 检查集计为本版已通过。
- Release 构建、ZIP/PKG 打包、最终签名 App 和本机 App 产品校验通过。
  安装后的 Host、Settings 和智能英文插件与最终签名 App 字节一致。

全应用 `SettingsUITests` 的标题按钮入口与预览检查已更新，但当前不是
隔离 UI 测试桌面，没有执行该套前台 XCUITest，也不宣称完成 VoiceOver
端到端人工验收。上述点击验证是生产控件的独立窗口事件测试。

## 本机交付

已安装 0.1.7 / build 8，确认进程从
`/Users/zga/Library/Input Methods/ZIME.app/Contents/MacOS/ZIME` 启动。
Hans 输入源检查为 `registered:selected-observation:selectable:path-unknown`，
实际位置另由进程路径验证。旧版 App 可从备份恢复：
`/Users/zga/Library/Input Methods/.zime-core-update.xxLdML/previous.app`。

安装前后真实设置文件 SHA-256 均为
`125d18d3d9f2953e230866ce6ac6877c1790d9410632c5b90a9d084cd7aa3b5b`。
文件仍保留旧 schema 14 字节；新版本读取时得到 schema 15 的设置模型，
下次正常保存会移除旧浏览字段。当前保持 16pt、每页 5 候选、双语竖排、
雾灰、整行选中与圆角。没有清空或重建用户学习词库。

| 文件（arm64） | 字节数 | SHA-256 |
| --- | ---: | --- |
| `ZIME-0.1.7-arm64.pkg` | 502,328,807 | `2b9667e329596dc644472355b897b7273d58c072b343aaf65f4f627ad722e821` |
| `ZIME-0.1.7-arm64.zip` | 502,342,224 | `6c95f48a356c009f98afbb87f245e604b943f104a39562e1239dbeb326ed5be5` |

交付目录：`/Volumes/Seagate ZP1000/Dev/ZIME-0.1.7-arm64/delivery/`。
开发预览仍为 Ad-hoc App 签名，PKG 未使用 Developer ID 签名或公证。
