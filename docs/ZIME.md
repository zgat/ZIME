# ZIME 0.1.13

ZIME is a macOS 13+ Apple-silicon input method with one shared local engine and
two system-visible modes:

- **ZIME Simplified Chinese** keeps Rime's `traditionalization` option off.
- **ZIME Traditional Chinese** turns the same option on.

Both modes use the same full-pinyin dictionary, user frequency, learned
phrases, English learning data, and settings under
`~/Library/Application Support/ZIME`. Caps Lock is raw ASCII; tapping Shift
switches between Chinese and Smart English.

## Bilingual candidate behavior

The source candidate uses regular-weight primary text and its local definition is gray
secondary text on every row, not only for the selected candidate. Chinese and
English default to a vertical list. Settings offers every page size from 3
through 9 in a menu. Existing pre-0.1.1 settings migrate once to vertical,
scrolling-only lists, preserving fonts, theme, page size and learning settings.
Candidate browsing is no longer a setting: the multi-page expansion state,
grid rendering, iterator, preview and key-trigger code have been removed.
Schema 15 accepts the old browsing field only for migration and omits it when
saving. Horizontal/vertical layout, page size and ordinary paging remain.
English input shows Chinese senses; Chinese input shows English definitions.
English definitions prefer an exact-case entry, then use a dictionary-wide
case-folded alias index generated automatically from the reviewed metadata
headwords. This includes arbitrary mixed-case heads such as `DoH`, `AppImage`
and `GraphQL`, not just uppercase acronyms. For example, `ime`, `Ime`, `IME`
and `iMe` all find the existing `IME` definition. Recognized alphabetic raw
candidates and English acronyms from the Chinese dictionary retain definition
metadata too. Lookup aliases do not change candidate spelling, commit text or
learning keys. Explicit case-sensitive exclusions remain authoritative, so
`US` does not inherit the unrelated pronoun definition of `us`.

Candidate lookup uses each candidate's actual spelling, not the active input
mode as a glyph filter. Regional labels express a preference with local fallback,
never a ban on translating a displayed word: 帥/髮 work in Simplified mode,
发/帅 work in Traditional mode, and 德士 still resolves to taxi in either mode.
Local and native dictionary glosses use a deterministic core projection that
distinguishes meanings, annotations and explicit headword references. Parentheses
are classified by content: known usage notes are separated, while semantic
qualifiers, complete grammatical definitions, literal formulas and unknown
content remain. Distinct meanings keep the ` / ` separator. Ordinary English
such as “see you tomorrow” is not treated as a headword reference.
Online fields bypass dictionary parsing entirely. Candidate annotations display
`腾讯:`, `百度:`, `DeepL:` or `ai:`; the source is separate metadata and never
part of a translation commit. The complete field remains one selectable result.
Translation Settings has a default-off “翻译显示完整注释” checkbox for hover/AX
details only. It uses the existing Apply/Discard workflow, migrates older provider
settings without resetting them, and does not access Keychain or invalidate the
translation cache merely because the display preference changes. Unknown words
still require dictionary coverage or an explicitly enabled translation provider;
the input method never invents a definition.

During candidate composition, minus pages up and equal/plus pages down.
At the first/last page these keys are consumed without a commit or state change.
Outside a real candidate menu, normal punctuation and raw/code input still apply.
The extra menu-bar mode indicator defaults off; macOS's input-source menu still
provides Settings and the current mode. Shift mode switching is unchanged.

When letters are pending, a plain digit without a corresponding visible-page
candidate joins the pending input instead of reaching the application early.
For example, with five candidates per page, `x` followed by `7` produces one
literal candidate `x7`; Enter commits the entire token once. Subsequent letters
and digits remain in that same token, and Backspace restores ordinary matching
when the last digit is removed. Valid numbered candidates still select normally
before entering this literal state; a forced-raw-only spelling accepts all digits.
Keypad digits follow the same rule, while idle digits and host modifier chords
are unchanged. Explicit Unicode/calculator/reverse-lookup routes take priority.
The Core projection installs the segmentor for both Chinese and Smart English,
including when an update retains an older language pack.

Settings → Input → Candidate shortcuts records actual keys instead of offering
fixed shortcut menus. The three independent actions are:

- **Switch source / translation** (Tab by default): changes the candidate side
  without inserting text.
- **Submit original input** (Enter by default, including keypad Enter):
  submits the pending original spelling, never the highlighted candidate on
  either side. `key` stays `key` and `nihao` stays `nihao`; number keys select
  “可以” or “你好”. Previously explicitly selected prefixes are preserved, with
  only the unconfirmed tail submitted raw. This does not train the unselected
  highlight. With no pending input, Enter remains the application's newline.
- **Smart completion** (Option-Tab by default): fills the highlighted English
  completion or spelling correction into marked input, without committing or
  learning it. Return submits that updated input. This action does not switch translation sides
  and can be left unassigned.

Click a shortcut and press the desired key or chord; Escape cancels recording,
and Delete clears the optional completion binding. Conflicts, bare typing keys,
editing keys and common system-reserved shortcuts are rejected. Recording is
window-local and requires no global keyboard or accessibility permission.
Schema 17 replaces the previous confirmation action with original-input
submission. Previously recorded keys are retained under the new action; the
retired `commitCandidate` field is read only for migration and never saved.
Old pass/navigate Tab behavior leaves completion unbound; old smart completion
receives Option-Tab. Rime's legacy fixed Tab action is
always projected as pass so it cannot compete with the recorded Host binding.

On the translation side, arrow keys move the highlight and 1–9 commit a row
directly. The configured 3–9 row page size applies to translations too; all
alternatives remain reachable through paging instead of being truncated at
nine rows. Unavailable numeric rows never select an invisible source candidate.
Escape or the toggle key returns to source candidates. If no available
definition exists, the source list remains active and ZIME reports
“无译文”. Definitions are never appended automatically. Outside composition,
these candidate shortcuts pass through to the application.

Space also submits original input rather than selecting a candidate; it adds
a space by default, with the existing Smart English trailing-space preference
still available. Return and Space dismiss zero-input predictions without
committing a suggestion, even after arrow navigation. Mouse and accessibility
candidate selection remain supported. Numeric selection and its page boundaries
are unchanged, including the literal alphanumeric behavior described above.

Selecting a translation first selects the corresponding source candidate in
Rime, preserving normal user-frequency learning. The chosen definition belongs
to that confirmed native segment, not to a global client-insertion override.
Partial selections retain their raw suffix; editing or reopening a segment
invalidates its previous translation, without affecting other confirmed segments.

## Local data and modern input features

- Local Data disclosure headers accept clicks on the arrow, label or trailing
  blank area through a single native button. Their content remains collapsed
  until requested, and inner actions retain their original confirmation flow.
- Wanxiang and the existing Linnet reviewed dictionaries provide full-pinyin
  phrases, initials/abbreviations, fuzzy spelling, context ranking, emoji,
  automatic phrase formation, and native Rime learning.
- Emoji participates in the same mode's candidate ranking as text. Choosing an
  emoji does not accidentally train its source Chinese word; either can move
  ahead through repeated selections. Display choices use reserved entries in
  the existing mode-owned learning database, included in native export/restore
  and disabled by the same learning switch. The bounded ranker runs after
  OpenCC and before Rime's final deduplicator; ordinary typing stays lazy.
- Chinese mode treats established same-span Chinese words, including initials
  and mixed full-pinyin/initial abbreviations, as Chinese intent by default.
  Common exact English can lead weak Chinese matches; explicit capitalization
  and the separate English mode preserve English intent. This is a cold-start
  policy, not a fixed position: native `user_table` selection counts let a
  learned exact English word pass less-used same-span Chinese words, while
  equally or more-used Chinese words retain priority. Native Chinese relative
  order and partial/custom candidate boundaries are preserved. Choosing Chinese
  again can reverse the preference. The Chinese mixed menu uses `linnet_zh`
  for Chinese entries and `linnet_zh_english` for English entries, under one
  mixed ranking policy and the Chinese learning strategy. Independent Smart
  English uses `linnet_en` and its own learning switch. Training in either mode
  never changes the other mode's counts. Clear Chinese Learning covers both
  Chinese-mode dictionaries; Clear English Learning affects Smart English only.
  Backup, portable import/export and restore preserve their separate identities.
- Linnet's reviewed English projection provides exact words, common English
  abbreviations such as `asap`, `btw`, `brb`, and `idk`, typo correction,
  completion, IPA, Chinese definitions, and next-word prediction.
- ZIME's build-time reverse index extracts exact Chinese dictionary senses and
  stores at most three frequency-ranked English words per sense in the same
  immutable local PredictEngine database. It does not fabricate word-by-word
  translations for sentences.
- A direct CC-CEDICT index adds 124,988 source entries, including simplified
  and traditional Chinese. Direct definitions take priority over the reverse
  English index. Schema revision 3 preserves all 199,654 source senses without
  prefix-based deletion and precomputes annotations for 197,976 spellings with
  the production Swift parser. Explicit aliases/abbreviations resolve by target
  spelling and optional reading when no direct meaning exists, with cycle/depth limits; usage, see-also and
  backward abbreviation references do not inherit meanings. Mixed legacy
  abbreviation lines retain their own English definition. An indexed runtime
  resolver provides the same behavior if no prepared projection exists.
  Spelling hints are never presented as missing translations.
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

Cloud translation is **off by default**. Enabling it and pressing the window's
shared Apply Changes button allows sending only untranslated visible-page candidates
(at most 9, at most 64 characters each). No clipboard, surrounding document,
application name or input history is read/sent. Requests are debounced 400 ms,
serialized with a one-second interval, cancelled on page/composition changes,
and never allowed to redirect. Local usable meanings, including resolved aliases,
prevent online requests and Keychain reads. Response bodies are capped at 64 KiB;
translation fields at 4,096 UTF-8 bytes, matching the native commit boundary.
Oversized/invalid fields are rejected whole, never silently truncated. Valid
punctuation, surrounding whitespace, tabs and newlines are retained verbatim.
Transient results remain in a bounded in-memory cache for ten minutes; errors
back off for 30 seconds. Network errors never block original-text input.

The test-connection button explicitly sends the fixed word `hello`, even if
the automatic cloud toggle is off. Merely opening Settings, entering a key or
selecting a provider does not make a request. API usage may incur provider fees.
Translation edits share the window's dirty-state, Apply, Discard and close-warning
contract. Credential deletion is confirmed and staged until Apply; Discard cancels it.
Changing the provider or endpoint clears unsaved credential drafts and cancels stale tests.

Language-pack/update code inherited from Linnet remains outside the candidate
translation path; it is not needed while typing. ZIME does not query or download
from Linnet's update catalog. Settings links to ZIME's releases until a separately
published, verified automatic-update catalog is available.

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
