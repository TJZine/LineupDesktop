---
title: Contributing
description: Learn how to contribute to Lineup and its documentation.
---
# Contributing

Lineup is open source. The app is written in Flutter and Dart.
Playback uses libmpv on Windows and macOS and Media3 on Android TV.
Changes go through pull requests on GitHub.
{ .lead }

## Project documents

- [docs/README.md](https://github.com/TJZine/LineupDesktop/blob/main/docs/README.md) — Documentation index: where each topic's current reference lives.
- [CONTRIBUTING.md](https://github.com/TJZine/LineupDesktop/blob/main/CONTRIBUTING.md) — How to propose changes, review expectations and issue reports.
- [docs/DEVELOPMENT.md](https://github.com/TJZine/LineupDesktop/blob/main/docs/DEVELOPMENT.md) — Toolchain, commands, test tiers and native builds.
- [docs/architecture.md](https://github.com/TJZine/LineupDesktop/blob/main/docs/architecture.md) — Ownership of app policy, saved data, playback and the native boundary.
- [docs/native-player-protocol.md](https://github.com/TJZine/LineupDesktop/blob/main/docs/native-player-protocol.md) — The contract between the app and each platform's player.
- [docs/windows-runtime.md](https://github.com/TJZine/LineupDesktop/blob/main/docs/windows-runtime.md) — Pinned libmpv and FFmpeg sources, licenses and packaging for Windows.
- [docs/macos-runtime.md](https://github.com/TJZine/LineupDesktop/blob/main/docs/macos-runtime.md) — The macOS player runtime and how to build it.
- [docs/android-runtime.md](https://github.com/TJZine/LineupDesktop/blob/main/docs/android-runtime.md) — The Android TV and Fire TV player, sideloading and device notes.
- [docs/licenses-and-rebuilding.md](https://github.com/TJZine/LineupDesktop/blob/main/docs/licenses-and-rebuilding.md) — Third-party licenses and how to rebuild shipped binaries.
- [docs/open-obligations.md](https://github.com/TJZine/LineupDesktop/blob/main/docs/open-obligations.md) — The register of unfinished product and release work.
- [docs/release-security.md](https://github.com/TJZine/LineupDesktop/blob/main/docs/release-security.md) — How release files are verified and published.
- [docs/repository-security.md](https://github.com/TJZine/LineupDesktop/blob/main/docs/repository-security.md) — Required checks and repository protections.

## Edit these docs

This site is built from the Markdown in `docs/` with Zensical.

```
python3 -m pip install --require-hashes -r tool/docs/requirements.txt
zensical serve
zensical build --clean --strict
python3 tool/docs/check_site.py site
```

## Security

Report security issues privately as described in the
[security policy](https://github.com/TJZine/LineupDesktop/blob/main/SECURITY.md).
