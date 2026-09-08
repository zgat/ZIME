# ZIME 0.1.15 / build 16 — installation and old-version cleanup

Date: 2026-09-08. The user requested installation followed by removal of old
versions. Functional changes and regression results are recorded in
[translation display validation](ZIME-TRANSLATION-DISPLAY-2026-09-08.md).

## Installation

- Rebuilt the tested source as 0.1.15 / build 16; `make release` passed.
- Staged a separate production-identity App and ad-hoc signed its nested code
  and bundles. `codesign --verify --deep --strict` and `verify_zime.sh APP`
  passed both before and after installation. This remains a local developer
  build, not a Developer ID notarized or published release.
- Temporarily selected the already enabled ABC layout and gracefully terminated
  the exact installed Host, PID 11135. No forced termination was necessary.
- Backed up the closed UserData directory, then reused the checked
  `LinnetDirectoryDelta.exchangeApp` Contents exchange. The registered App
  directory inode remained 94841227. The UserData tree matched its snapshot
  byte-for-byte before the new Host started; no language packs were replaced.
- Started the installed App with `open -g`, without the hide flag `-j`, and
  restored the original `com.zime.inputmethod.ZIME.Hans` input source.
- After cleanup, PID 18849 was still running from the installed path with
  `hidden=false`. Its Host and Rime/plugin mappings used the installed bundle.
  The input-source observer confirmed selected/selectable status. No input
  source registration, unregistration or enablement change was needed.
- The settings JSON SHA-256 remained unchanged:
  `125d18d3d9f2953e230866ce6ac6877c1790d9410632c5b90a9d084cd7aa3b5b`.

Installed and retained current-source Host executable SHA-256:
`16cc5cfe6f3577b0b3f6a75916335ef333078f39d0115f26a8487fb3abc0a58d`.

The current source App is retained at
`/Volumes/Seagate ZP1000/Dev/ZIME-0.1.15-arm64/core/ZIME.app`.

## Recoverable cleanup

Only after installation and runtime verification, moved these exact inventoried
targets to macOS Trash using FileManager:

- 16 versioned build/delivery directories: 0.1.0 through 0.1.14, including the
  separate 0.1.0 registration-fix directory.
- 13 previous-App backups in the per-user Input Methods directory. Eleven
  wrappers contained only a previous App and were moved whole; two wrappers
  also contained user-data snapshots, so only their previous App was moved.

All 29 original targets were absent on recheck and all 29 Trash destinations
existed. The only remaining versioned delivery directory is 0.1.15. Trash was
not emptied, so this is reversible removal, not a disk-space reclamation claim.
The repository, current App, dictionaries, learning data, settings and user-data
backups remain. Git history and remote releases were not deleted or changed.

User-data backups remain in the hidden `.zime-core-0.1.14.GDbYWw` and
`.zime-core-0.1.15.AtQKl2` directories under the user's Input Methods directory;
neither contains an old App now. No reboot, Git commit or push was performed.
Real-document candidate input and WeChat screenshot behavior were not automated
as part of installation verification.
