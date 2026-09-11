# ZIME 0.1.20 — 拼音纠错、混合输入与候选学习

2026-09-11，build 21。适用于 Apple Silicon、macOS 13+。
本次汇总 0.1.18–0.1.20 的本地修复，上一公开版本为 0.1.17。

## 主要修复

- **`nui → 牛`**：补上全拼末尾 `iu` 换位纠错，词组 `nuinai → 牛奶` 同样生效。
  冷门英文 `niu / nui` 不再因中文只匹配首字母而挤到前面。
  `dui / gui / hui / shui / tui` 等合法拼音保持原样，双拼键位不变。
- **`wov → 我v`**：中文前缀后的字母没有可靠整段匹配时，提供保留尾串的完整候选。
  `woi → 我i`、`nihaov → 你好v` 同理；数字键一次提交，Enter 仍提交原始输入。
  第一页保留原生分段选词入口，调整每页 3–9 行不丢失备选的学习排序。
- **不再把 `woi` 扩成“我IME”**：拒绝未输完整英文缩写的混合组句，
  但完整 `woime → 我IME`、`woibm → 我IBM` 仍可使用。
- **精确英文与学习排序更一致**：冷启动 `i` 的精确候选 `I` 不再被 `IME / IBM`
  补全抢占；同范围的英文精确匹配优先于普通别名和补全。主动选择仍可改变顺序，
  排序不是固定写死的。
- **学习归属于实际输入**：在 `ime` 下选 `IME` 不会自动推高它在 `i` 下的位置；
  在 `nui` 下选英文 `niu` 仍可学习。中文模式内中文、英文、Emoji 一起排序，
  独立英文模式单独学习；支持双向调整、跨重启保存和关闭学习。
  “我v”不会被错误地写成原生 `wo` 的词条。

## 下载与升级

| 下载 | 用途 |
| --- | --- |
| [ZIME-0.1.20-arm64.zip](https://github.com/zgat/ZIME/releases/download/v0.1.20/ZIME-0.1.20-arm64.zip) | 完整 App、离线词库和模型；首次安装推荐 |
| [ZIME-0.1.20-arm64.pkg](https://github.com/zgat/ZIME/releases/download/v0.1.20/ZIME-0.1.20-arm64.pkg) | 同一套完整内容，通过 macOS 安装器安装 |
| [ZIME-0.1.20-arm64-core.zip](https://github.com/zgat/ZIME/releases/download/v0.1.20/ZIME-0.1.20-arm64-core.zip) | 已有兼容完整数据时，只更新 App 和运行库 |

已有 0.1.17 完整数据可只更新 Core；首次安装或仍使用更早词库时选择完整包。
本次未变更上游锁定版本、词库或 LTS 模型。新的全拼规则随 Core 重新部署生效，
无需清空学习数据；设置、个人词频和回滚材料继续保留。

安装前保存正在输入的内容并关闭 ZIME 设置。具体操作与恢复方式见
[安装说明](https://github.com/zgat/ZIME/blob/v0.1.20/docs/ZIME-INSTALL.md)。
GitHub 自动生成的 Source code 归档不是安装包。

## 验证与限制

修复经过隔离的真实 Rime 回归：纠错、混输、3–9 行分页、数字选择、原文提交、
繁体、大小写、Emoji、跨进程学习及中英文模式隔离；完整 Swift 设置/UI 测试通过。
本机 Core 升级后，以安装的运行库和部署方案在空白学习目录回放 `nui`，得到
`牛、🐮、扭、钮、纽…`。详细记录：
[缩写与组句边界](https://github.com/zgat/ZIME/blob/v0.1.20/docs/ZIME-CANDIDATE-BOUNDARIES-2026-09-10.md)、
[完整尾串候选](https://github.com/zgat/ZIME/blob/v0.1.20/docs/ZIME-LITERAL-MIXED-2026-09-10.md)、
[换位纠错与排序](https://github.com/zgat/ZIME/blob/v0.1.20/docs/ZIME-TRANSPOSITION-2026-09-10.md)。

完整 ZIP、PKG 和 Core ZIP 从同一源码提交构建；下载后使用 `SHA256SUMS` 核对，
`manifest.json` 记录源码提交、尺寸与哈希。包级验证不等于所有 macOS 版本和应用均已验收。

仍为 **Ad-hoc 开发预览**：App 未使用 Apple Developer ID 签名，PKG 未签名，
均未经过 Apple 公证；未开启自动更新频道。首次输入源授权需要按 macOS 提示完成，
不要全局关闭系统安全检查。微信截图对候选窗的捕获限制没有新增修复承诺。
本次未扩大翻译词库覆盖率，也未改变 Tab 切换、数字选词、Enter 原文或云翻译隐私边界。

## 来源与许可证

ZIME 源码按 GPL-3.0-or-later 发布。万象字词表与 LTS 模型沿用 0.1.17 的锁定输入，
来源于 [amzxyz/rime-wanxiang](https://github.com/amzxyz/rime-wanxiang) 和
[amzxyz/RIME-LMDG](https://github.com/amzxyz/RIME-LMDG)，按 CC BY 4.0 提供；
CC-CEDICT 改编数据为 CC BY-SA 4.0。精确来源、修改说明及完整归属见仓库
`upstreams.lock.json`、`THIRD_PARTY_NOTICES.md` 和 App 内 `ZIMERelease/LICENSES`。
