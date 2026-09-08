# Translation display validation — 2026-09-08

## Behavior

- Candidate annotation looks up the actual simplified or traditional spelling.
  Region preferences select senses, but no longer prohibit translating another
  script or leave a regional-only headword untranslated (for example 德士 → taxi).
- Candidate rows and explicitly selected translations share the same core
  meanings. 你 / 妳 → you; explanatory parentheses and pronunciation references
  are excluded. Distinct meanings and slash separators remain; literal spelling,
  chemical formulas and native English IPA are preserved.
- Settings → 翻译 → 翻译显示完整注释 defaults off. It only exposes original
  dictionary details in hover/accessibility help, never in committed text.
  Apply/Discard and old saved provider configurations remain supported.
- Offline misses and unavailable cloud results both display 无译文. Pending
  requests still display 译文查询中…. These hints are not selectable translations.
- The source dictionary is unchanged. Genuine missing definitions remain missing;
  this change does not guarantee coverage for arbitrary phrases or enable cloud
  translation automatically. A display-only change does not access credentials,
  clear cached translations or send another request.

## Verification

- `bash tests/verify_zime_translation.sh`: PASS. Includes 124,988 source-entry
  identity checks, core-meaning projection, simplified/traditional and regional
  fallback, legacy configuration migration, settings persistence, mocked cloud
  timeout/cache behavior, and production Host numeric-selection routing.
- `bash tests/verify_zime.sh`: PASS.
- `bash tests/verify_candidate_window_interaction.sh --diagnose-only`: PASS.
  Includes 3–9 rows, multiple font sizes, core gloss layout, native tooltip and
  accessibility detail toggling, and removal of stale help after disabling it.
  This run does not verify or regenerate README gallery images.
- `LinnetCandidatePresentationTests`: PASS (standalone compile/run).
- `make release`: PASS; local development build only. Existing SDK notices about
  optional simulator support and AppIntents did not prevent the macOS build.
- `git diff --check`: PASS.

No real API calls or credential access were used for these tests. The installed
input method was not replaced, restarted or registered, and nothing was committed
or pushed.

Subsequently installed as 0.1.15 / build 16 after explicit user authorization;
see [installation and cleanup verification](ZIME-0.1.15-VALIDATION.md).
