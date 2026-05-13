# Packaging And Release Gates

Lineup Desktop has an internal Windows x64 unpacked package proof for maintainer
validation. It has no public release pipeline yet.

## Intended Release Shape

- Windows x64 first.
- Signed NSIS installer for public distribution.
- Unsigned dev, unpacked, or portable internal artifacts are acceptable before
  MVP while the maintainer is the primary tester.
- Auto-update is deferred until signing, release channels, rollback behavior,
  and native binary layout are stable.

## Internal Windows Package Proof

RD-18 Unit 1 completed the internal Windows x64 package layout on 2026-05-13.
The reviewed tooling stages only
`out/rd-18-windows-internal/lineup-desktop-0.0.0-win32-x64/` and keeps generated
output ignored/local.

Observed Windows x64 closeout proof:

- `npm run build:electron` passed before packaging.
- `node tools/package-windows-internal.mjs --out out/rd-18-windows-internal`
  passed and produced the internal package directory.
- `node tools/verify-windows-internal-package.mjs --package
  out/rd-18-windows-internal/lineup-desktop-0.0.0-win32-x64 --manifest
  out/rd-18-windows-internal/lineup-desktop-0.0.0-win32-x64/resources/lineup-desktop-provenance.json`
  passed against the generated artifact.
- The artifact contains `LineupDesktop.exe`, unpacked `resources/app`,
  `resources/lineup-desktop-provenance.json`, `resources/checksums.sha256`,
  `resources/third-party-notices-internal.json`,
  `resources/native-helper/PRODUCTION_HELPER_BLOCKED.txt`, and
  `resources/media-binaries/REDISTRIBUTION_BLOCKED.txt`.
- Provenance records Electron `42.0.0`, bundled Node `24.15.0`, Chrome
  `148.0.7778.96`, package metadata, lockfile package count, build input
  checksums, artifact checksums, internal notice status, blocked
  native-helper/media status, and the RD-17 support-bundle redaction proof
  reference.

RD-18 Unit 1 intentionally does not add package scripts, dependencies,
lockfile changes, signing config, update metadata, native media binaries, Plex
behavior, renderer/preload/IPC contracts, runtime behavior, or a public release
artifact.

## Public Distribution Blockers

Do not ship a public build until this repo records:

- exact Electron and bundled Node versions
- exact production native helper and media binary versions
- public-release binary provenance and checksums
- GPL/LGPL and third-party notice obligations
- Windows code-signing plan
- installer layout and native binary loading proof
- redacted diagnostics export proof
