# ZIME optimization working snapshot — 2026-09-08

This is an uninstalled development snapshot based on 0.1.13/build 14, not a
new release or an update to the previously delivered 0.1.13 package.

## Changes

- Translation selection is native-segment scoped. Confirmed source/translated
  prefixes, raw tails and source learning survive partial selection; reopening
  a segment clears its old translated replacement.
- Translation candidates obey the selected 3–9 row page size and keep all
  alternatives reachable. Invalid digits cannot select hidden source rows.
  Modifier chords pass through after explicitly configured shortcuts.
- Translation API settings now share Apply/Discard/close warnings with other
  settings. Keychain deletion is staged, and stale connection tests cannot
  repaint another provider's draft. No live provider requests were made in tests.
- Hidden translations skip lookup; default configuration has a stable cache
  identity; bounded cloud-cache eviction no longer clears the entire cache.
- Emoji and text learn together within the active input mode, using existing
  local user dictionaries. Emoji conversion is identified by its source marker,
  not a limited Unicode range heuristic. Choosing an emoji does not teach Rime
  that the source Chinese word was chosen. Native export/import preserves the
  displayed choices; learning-off and mode isolation have executable tests.
- Candidate ranking runs before the final native uniquifier. The first version
  placed it after uniquifier and exposed duplicate raw candidates; the `x0`
  regression caught this, and the full alphanumeric suite passes after repair.
- ZIME's settings no longer query/download the inherited Linnet update catalog.
  The releases link is manual; independent automatic updates are not implemented.

## Verification

Passed on the final source snapshot:

- Native runtime/plugin build and `make release` (unsigned local-build identity).
- Complete `tests/verify_swift_units.sh`, including appearance preview, candidate
  window interactions, update-channel guards, Settings transactions and IPC.
- `tests/verify_zime.sh` and `tests/verify_zime_translation.sh`: mock transport
  only, plus executable extraction of the production Host routing methods.
- Native `--zime-shortcuts-probe`, `--zime-bilingual-probe`, `--zime-paging-probe`,
  `--zime-case-probe` and `--zime-alphanumeric-probe`. These include emoji
  promotion/text re-promotion, learning-off, fresh-process persistence,
  export/import, translated-prefix/raw-tail composition and reopening.
- `--mixed-latency-probe`: 8,192 samples of `xuexicsjiting`, per-key p95
  3.290 ms and p99 3.594 ms. This is a native engine measurement, not an
  end-to-end WeChat typing measurement or a controlled before/after comparison.
- Candidate fixture presentation: cold 61.38 ms, steady p95 5.93 ms,
  maximum 6.37 ms. Cold presentation remains more expensive than steady state;
  no claim is made that startup/prewarming work is complete.

Generated light/dark Settings theme previews were inspected. These fixtures do
not replace an installed input-method or real screenshot-tool acceptance test.

The retained Linnet umbrella checks are not green: `verify_rime_runtime.sh`
still asserts retired double-pinyin behavior (`linnet_zh` / `xq`), and
`verify_runtime_footprint.sh` still expects the old nine-schema inventory.
Do not represent passing ZIME-specific probes as a pass of those legacy gates.
SwiftLint is unavailable on this machine; no lint success is claimed.

## WeChat screenshot investigation

Reported shortcut: Shift+Option+S. After starting/cancelling capture, both
displays lose the candidate panel without restoration; only the primary
display's frozen screenshot includes the panel.

`hidesOnDeactivate` is explicitly false. Structural IMK lifecycle diagnostics
record activation, deactivation, commit and palette-hide events, with only a
boolean for pending input. They do not record keys, candidate text, document
content, application identity or clipboard contents. No window-level change,
global shortcut hook or cross-application composition retention was added.

After the user explicitly installs a new build, reproduce while running:

```sh
log stream --level info --predicate 'subsystem == "com.zime.inputmethod.ZIME" AND category == "InputLifecycle"'
```

The event sequence and whether raw pinyin entered the document still need to
be observed. This is diagnostic work, not a verified WeChat screenshot fix.
No installed app was replaced, no input-method process was restarted, no user
learning data was cleared, and nothing was pushed to GitHub in this turn.
