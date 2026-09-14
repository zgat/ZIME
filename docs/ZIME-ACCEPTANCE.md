# ZIME 真实验收清单

自动化回归不能证明下列场景已经通过。每项填写测试者、准确系统/App 版本、
候选源码 revision、日期以及脱敏截图/日志/操作记录；未执行记为 NOT_EXERCISED，
失败记为 FAIL，不使用“跳过即通过”。

## 必测场景

| 范围 | 操作与预期 |
| --- | --- |
| macOS 13、14、15、26 | 每个系统实际安装、启用、输入、切换和打开设置；仅编译 deployment target 不算运行验证 |
| Settings 点击 | 隔离桌面执行完整 SettingsUITests；分页数 3–9、主题/高亮/圆角、快捷键冲突、翻译应用/撤销与数据折叠 |
| TextEdit、Safari、Chrome、VS Code、Notes、Terminal | 分别验证 nihao/key/wov/nui/ime/IME/x70；数字/空格选词、回车原文、Tab 原译文、删除、取消、快捷键和失焦 |
| 微信主屏/副屏截图 | 两屏分别用 Shift-Option-S；记录冻结时候选是否可见、取消后状态，对照 macOS 原生输入法 |
| 首装、Core 升级、完整升级、重复升级、卸载 | 专用测试账户；检查版本/签名/输入源、设置与学习保留、Data/Runtime 替换边界、异常回滚；卸载不得删个人数据 |
| OpenAI 兼容、DeepL、百度、腾讯 | 分别显式授权少量固定请求，检查双向译文、来源标签、错误/超时/额度提示；模拟请求不替代真实服务验收 |
| 长时间运行 | 记录至少一小时实际输入、切换、休眠唤醒、内存与候选响应；4,096 轮原生压力回归不能代替耐久性验收 |

Settings 完整点击测试必须在 CI 或确实隔离的桌面执行，不能在日常账户伪造环境标记。
macOS 15/26 的远端 CI 配置不代表已经运行，更不代表 macOS 13/14 已实测。

## 在线烟雾测试（需先同意）

`tests/verify_zime_online.sh --allow-network` 读取当前已启用服务的配置及对应钥匙串凭据，
仅发送“你好”和“hello”两次请求，可能计费。不会写设置、打印密钥/地址/响应或提交个人输入。
不传授权参数会在读取配置或凭据前以 64 退出；服务禁用以 2 退出，均是未执行，不是 PASS。
成功只表示真实请求和响应解码通过，不保证翻译质量。此脚本不加入默认或 CI 回归。

## 验收收据

`tests/verify_zime_acceptance.rb --template` 输出全为 NOT_EXERCISED 的 JSON 模板。
维护者填写后运行：

```sh
tests/verify_zime_acceptance.rb /absolute/path/to/receipt.json <full-tested-source-revision>
```

只要有未执行、失败、缺失、重复或无证据的项目，就以非零退出。
工具只能核对收据结构与声明，不能代替审核者确认截图和日志真实性。
发布候选验收和本地测试通过应分别报告；不要伪造 PASS 或拿旧 revision 的结果签收新版本。
