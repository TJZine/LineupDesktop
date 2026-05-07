# Packaging And Release Gates

Lineup Desktop has no public release pipeline yet.

## Intended Release Shape

- Windows x64 first.
- Signed NSIS installer for public distribution.
- Unsigned dev, unpacked, or portable internal artifacts are acceptable before
  MVP while the maintainer is the primary tester.
- Auto-update is deferred until signing, release channels, rollback behavior,
  and native binary layout are stable.

## Public Distribution Blockers

Do not ship a public build until this repo records:

- exact Electron and bundled Node versions
- exact native helper and media binary versions
- binary provenance and checksums
- GPL/LGPL and third-party notice obligations
- Windows code-signing plan
- installer layout and native binary loading proof
- redacted diagnostics export proof
