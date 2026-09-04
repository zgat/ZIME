# ZIME 0.1

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
secondary text. English input shows Chinese senses. Chinese full-pinyin input
shows up to two English glosses inline while retaining up to three ordered
choices internally.

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
- Linnet's reviewed English projection provides exact words, common English
  abbreviations such as `asap`, `btw`, `brb`, and `idk`, typo correction,
  completion, IPA, Chinese definitions, and next-word prediction.
- ZIME's build-time reverse index extracts exact Chinese dictionary senses and
  stores at most three frequency-ranked English words per sense in the same
  immutable local PredictEngine database. It does not fabricate word-by-word
  translations for sentences.
- Runtime lookups use the immutable memory-mapped index plus Rime's local user
  databases. No keystroke or candidate text leaves the Mac.

## Privacy boundary

`ZIMECloudTranslationProvider` is the only source-level extension point for a
future remote translator. Version 0.1 installs only
`ZIMENullCloudTranslationProvider`, which always returns an empty result. The
candidate path contains no HTTP client and makes no network request.

Language-pack/update code inherited from Linnet remains outside the candidate
translation path; it is not needed while typing. Cloud translation is not
implemented.

## Build and verification

Initialize the pinned submodules, then run:

```sh
./action-build.sh release
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
