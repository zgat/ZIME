# ZIME 0.1.14 / build 15 — installation validation

Date: 2026-09-08. The user explicitly authorized installation after the
[optimization validation](ZIME-OPTIMIZATION-2026-09-08.md).

- Rebuilt Release after updating only version/build identifiers to 0.1.14/15.
  The functional source is the tested optimization snapshot.
- Staged a separate production-identity App and ad-hoc signed inner code and
  both bundles. `codesign --verify --deep --strict` and `verify_zime.sh APP` passed.
  This is a local developer preview, not Developer ID notarization or publication.
- Updated only `/Users/zga/Library/Input Methods/ZIME.app`. No dictionary pack,
  translation preference or Keychain credential was replaced.
- Settings was not running. Temporarily selected the already enabled ABC layout,
  requested graceful termination of the exact installed Host and retained user
  data backups. macOS relaunched the old Host once; the first swap guard rejected
  the update without changing the installed App. A second graceful exit followed
  immediately by atomic publication succeeded.
- Reused `LinnetDirectoryDelta.exchangeApp`: exchanged complete Contents rather
  than moving the registered App directory. Its inode remained `94841227`.
- The final pre-start user-data tree matched its backup byte-for-byte. The
  settings JSON SHA-256 before and after startup remained
  `125d18d3d9f2953e230866ce6ac6877c1790d9410632c5b90a9d084cd7aa3b5b`.
- New Host PID 8617 was running from the installed path. Its live mappings
  included the installed librime and smart-English plugin. The Settings socket
  was present; deployed Chinese/English schemas included `zime_display_learning`
  before `uniquifier`, and native Tab behavior was `pass`.
- Restored `com.zime.inputmethod.ZIME.Hans`. Both direct TIS observation and the
  registration inspector confirmed that it was selected and selectable. Existing
  input-source enablement was preserved; no source was registered or unregistered.

Installed and staged Host executable SHA-256 matched:
`9dde3dba73df3b8e6ce71db2d3382e1f2ae0a49f82f6dd05a43e55c3a0330f78`.

## Recovery artifacts

- Signed current source App:
  `/Volumes/Seagate ZP1000/Dev/ZIME-0.1.14-arm64/core/ZIME.app`
- Signed previous 0.1.10 App:
  `/Users/zga/Library/Input Methods/.zime-core-0.1.14.GDbYWw/previous.app`
- Closed pre-update user-data snapshot:
  `/Users/zga/Library/Input Methods/.zime-core-0.1.14.GDbYWw/UserData-before-final`

These backups were retained, not registered or launched. Do not launch the
previous App from its backup path. A rollback should preserve the installed App
directory using the same checked Contents exchange with the Host inactive.

No GitHub push or reboot was performed. No synthetic text was entered into a
real document. WeChat screenshot behavior still needs user-side reproduction;
installation does not turn the diagnostic-only work into a verified fix.

## Superseded on 2026-09-08

0.1.15 / build 16 has since been installed. At the user's request, the old source
App directory and previous-App backup listed above were moved to macOS Trash
after verification; the user-data snapshots remain in place. See
[0.1.15 installation and cleanup](ZIME-0.1.15-VALIDATION.md).
