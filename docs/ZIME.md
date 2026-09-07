# ZIME 0.1.2

ZIME is a macOS 13+ Apple-silicon input method with one shared local engine and
two system-visible modes:

- **ZIME Simplified Chinese** keeps Rime's `traditionalization` option off.
- **ZIME Traditional Chinese** turns the same option on.

Both modes use the same full-pinyin dictionary, user frequency, learned
phrases, English learning data, and settings under
`~/Library/Application Support/ZIME`. Caps Lock is raw ASCII; tapping Shift
switches between Chinese and Smart English.

## Bilingual candidate behavior

The source candidate is the bold primary text and its local definition is gray
secondary text on every row, not only for the selected candidate. Chinese and
English default to a vertical list. Settings offers every page size from 3
through 9 in a menu. Existing pre-0.1.1 settings migrate once to vertical,
scrolling-only lists, preserving fonts, theme, page size and learning settings.
English input shows Chinese senses; Chinese input shows English definitions.

During candidate composition, minus pages up and equal/plus pages down.
At the first/last page these keys are consumed without a commit or state change.
Outside a real candidate menu, normal punctuation and raw/code input still apply.
The extra menu-bar mode indicator defaults off; macOS's input-source menu still
provides Settings and the current mode. Shift mode switching is unchanged.

The default translation-side key is Tab. Option-Return can be selected instead
in Settings. On the translation side, arrow keys move the highlight, 1–9
commit a row directly, and the configured Return or Space key commits the
highlighted row. Escape or the toggle key returns to source candidates. If no
local definition exists, the source list remains active and ZIME reports
“暂无本地译文”. Definitions are never appended automatically.

Selecting a translation first selects the corresponding source candidate in
Rime, preserving normal user-frequency learning, then substitutes only the
chosen definition at the client insertion boundary.

## Local data and modern input features

- Wanxiang and the existing Linnet reviewed dictionaries provide full-pinyin
  phrases, initials/abbreviations, fuzzy spelling, context ranking, emoji,
  automatic phrase formation, and native Rime learning.
- Chinese mode treats established same-span Chinese words, including initials
  and mixed full-pinyin/initial abbreviations, as Chinese intent. Native learned
  `user_phrase` entries outrank exact English independently of their static word
  frequency. Only common exact English can lead weak Chinese matches; explicit
  capitalization and the separate English mode preserve English intent.
- Linnet's reviewed English projection provides exact words, common English
  abbreviations such as `asap`, `btw`, `brb`, and `idk`, typo correction,
  completion, IPA, Chinese definitions, and next-word prediction.
- ZIME's build-time reverse index extracts exact Chinese dictionary senses and
  stores at most three frequency-ranked English words per sense in the same
  immutable local PredictEngine database. It does not fabricate word-by-word
  translations for sentences.
- A direct CC-CEDICT index adds 124,988 source entries, including simplified
  and traditional Chinese. Direct definitions take priority over the reverse
  English index. Spelling hints are never presented as missing translations.
- Runtime lookups use read-only indexed databases and bounded hot caches plus
  Rime's local user databases. By default no candidate text leaves the Mac.

## Privacy boundary

The independent **翻译** Settings tab supports OpenAI-compatible Chat
Completions endpoints (user-specified HTTPS base URL and model), DeepL API
Free/Pro, Baidu general translation and Tencent TextTranslate. Credentials are
stored in macOS Keychain, scoped to provider and endpoint; nonsecret options
are in the `com.zime.translation` preferences domain. Both remain outside the
language-data/portable backup path. Changing endpoint requires credentials for
that endpoint. Ad-hoc builds may require a Keychain access confirmation.

Cloud translation is **off by default**. Enabling it and pressing this tab's
own Save button allows sending only untranslated visible-page candidates
(at most 9, at most 64 characters each). No clipboard, surrounding document,
application name or input history is read/sent. Requests are debounced 400 ms,
serialized with a one-second interval, cancelled on page/composition changes,
and never allowed to redirect. Responses are capped at 64 KiB / 256 characters.
Transient results remain in a bounded in-memory cache for ten minutes; errors
back off for 30 seconds. Network errors never block original-text input.

The test-connection button explicitly sends the fixed word `hello`, even if
the automatic cloud toggle is off. Merely opening Settings, entering a key or
selecting a provider does not make a request. API usage may incur provider fees.

Language-pack/update code inherited from Linnet remains outside the candidate
translation path; it is not needed while typing.

API request formats were checked against [OpenAI Chat Completions](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create),
[DeepL](https://developers.deepl.com/api-reference/translate/request-translation),
[Baidu](https://api.fanyi.baidu.com/doc/23) and
[Tencent's official API manual](https://main.qcloudimg.com/raw/document/product/pdf/551_7376_cn.pdf).
Offline contract tests do not substitute for a live test with the user's own credentials.

## Build and verification

Initialize the pinned submodules, then run:

```sh
./action-build.sh release
tests/verify_zime_translation.sh
tests/verify_swift_units.sh
tests/verify_rime_runtime.sh
```

The local build product is `build/Local/Build/Products/Release/ZIME.app`.
Install it for the current user
at `~/Library/Input Methods/ZIME.app`, then add either ZIME input source in
System Settings. Do not launch a build-tree copy as an input-method host; ZIME
intentionally rejects that path.

The delivery includes `scripts/uninstall-zime`. It removes only the installed
app by default and preserves learning data. Pass `--purge-data` to remove the
exact ZIME Application Support directory as well.

For a production-identity App, ZIP, current-user PKG and install instructions,
run `scripts/build-zime-delivery APP OUTPUT_DIRECTORY`. The resulting preview
is ad-hoc signed and deliberately not represented as Developer ID notarized.

See [0.1.1 validation and dictionary audit](ZIME-0.1.1-VALIDATION.md) for the
verified scope, remaining visual-test limitation, dictionary sources and licenses.
