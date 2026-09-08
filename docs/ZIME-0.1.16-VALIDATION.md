# ZIME 0.1.16 / build 17 — local installation

Date: 2026-09-08. User explicitly requested installation of the translation
source labels and lossless local-lexicon parser described in
[implementation validation](ZIME-TRANSLATION-SOURCES-2026-09-08.md).

- `make release` and `tests/verify_zime_translation.sh` passed after the version
  bump. Staged a separate production-identity App; all eight Mach-O files were
  arm64 and ad-hoc signed. Deep/strict code-signature and `verify_zime.sh APP`
  checks passed before and after installation. This is a local developer build,
  not a notarized or published release.
- The first exchange was safely rejected because Settings PID 35074 was still
  running. Restored the original input source, then requested normal Settings
  termination. It exited without an unsaved-changes decision or forced kill.
- Temporarily selected ABC and gracefully terminated the exact installed Host,
  PID 18849. Backed up closed UserData and exchanged complete App Contents using
  `LinnetDirectoryDelta.exchangeApp`. The registered App inode stayed 94841227;
  UserData remained byte-identical to the snapshot before the new Host started.
- Started with `open -g` (no hide flag), restored
  `com.zime.inputmethod.ZIME.Hans`, and verified new PID 42601 at the installed
  path with `hidden=false`. Installed version is 0.1.16 / 17; lexicon schema is 3.
- Settings JSON and the active language-data manifest hashes stayed unchanged.
  No language packs, user learning, cloud configuration or credentials were
  replaced. No actual API calls, document input or screenshot behavior were
  exercised during this installation. No reboot, commit, push or cleanup.

Installed App: `/Users/zga/Library/Input Methods/ZIME.app`

Retained source App:
`/Volumes/Seagate ZP1000/Dev/ZIME-0.1.16-arm64/core/ZIME.app`

Recoverable old App and closed UserData snapshot:
`/Users/zga/Library/Input Methods/.zime-core-0.1.16.gOraq0/{previous.app,UserData-before}`

Installed and retained source Host SHA-256:
`24ad05fc95dcfc0dd9992e0d59937713be0237919663a9863d6abf328be12f1d`

Installed lexicon SHA-256:
`4e1caa9149d212ceb411c38a52af89f8f3c3a5a456dab13b84ab9d71e872979a`

Settings JSON SHA-256:
`125d18d3d9f2953e230866ce6ac6877c1790d9410632c5b90a9d084cd7aa3b5b`

Active language-data manifest SHA-256:
`b004016783d8b9bdd56f4759e25dae02c02225283b5d1878c705240fbdd14866`
