<p align="center">
  <img src="assets/branding/lineup-wordmark.png" alt="Lineup Desktop" width="420">
</p>

<p align="center">
  <strong>A native desktop client for building and watching Plex-powered virtual TV channels.</strong>
</p>

<p align="center">
  <a href="https://github.com/TJZine/LineupDesktop/actions/workflows/ci.yml?query=branch%3Amain">
    <img src="https://github.com/TJZine/LineupDesktop/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI status">
  </a>
  <a href="LICENSE">
    <img src="https://img.shields.io/badge/license-Apache--2.0-blue.svg" alt="Apache 2.0 license">
  </a>
  <img src="https://img.shields.io/badge/status-pre--release-orange.svg" alt="Pre-release status">
</p>

> [!IMPORTANT]
> Lineup Desktop is under active development. Use the official
> [GitHub Releases](https://github.com/TJZine/LineupDesktop/releases) page for
> any public build. If no application release is listed, no public build is
> available yet. See [the reconciled backlog](docs/open-obligations.md) for the
> remaining Windows and Android release acceptance work.

Lineup Desktop turns a Plex library into a deterministic, television-style
lineup. It combines channel creation, a responsive electronic program guide,
and native desktop playback while keeping product behavior in Flutter/Dart and
the native media/platform boundary deliberately narrow.

## Highlights

- Plex PIN sign-in, Plex Home profiles, server discovery, and secure credential
  storage
- A guided Channel Builder with library, playlist, collection, genre, decade,
  studio, actor, and director strategies
- Custom channels built from an entire library or hand-picked media
- Classic picture-in-picture Guide layout with a responsive schedule surface
- Native Windows, macOS and Android TV playback with an OSD, mini Guide, channel entry, seeking,
  track selection, sleep timer, and fullscreen controls
- Four themes, reduced motion, larger focus indicators, and optional DVR
  playback controls
- Bounded, credential-safe diagnostics intended for support and testing

## Platform status

| Platform | Current status |
| --- | --- |
| Windows 10/11 x64 | Primary desktop target. The public-release path is an unsigned portable ZIP. Use a current GPU driver or Vulkan Runtime providing `vulkan-1.dll`. Final real-hardware and release acceptance remains pending. |
| macOS, Apple Silicon | Native libmpv playback, Guide/PiP, HDR presentation and Mac integration are implemented for development/private testing. The supported minimum is macOS 14 Sonoma; the preserved beta candidate still builds with a macOS 12 deployment target, and runtime coverage is recorded on macOS 27. Sonoma hardware validation and signed distribution remain open. |
| Android TV / Google TV / Android-based Fire TV | Sideloaded APK for Android 9+ on ARM (`armeabi-v7a` and `arm64-v8a`) with a Kotlin Media3 player adapter and a D-pad interface following the [TV UI decisions](docs/design/tv-ui-decisions.md). Vega OS Fire TV devices cannot run APKs. Direct Play and couch acceptance remain platform gates. See [Android runtime](docs/android-runtime.md). |
| Apple TV | Feasibility research only; no tvOS implementation. |
| Linux | Not currently targeted. |

See [Architecture](docs/architecture.md) for the ownership model and
[Windows Native Acceptance](docs/windows-native-validation.md) for the evidence
still required before broader release claims.

## First run

A private test build guides the user through:

1. Link a Plex account with a QR code or four-character PIN.
2. Choose a Plex Home profile, including protected-profile PIN entry.
3. Select a reachable Plex Media Server.
4. Select libraries and build or review the initial channel lineup.

The main application then provides **Guide**, **Channels**, **Settings**,
**Diagnostics**, and **Player** destinations. The
[User Guide](docs/user-guide.md) documents the complete flow, controls,
settings, privacy behavior, and troubleshooting steps.

## Getting a build

For a public build, use the [GitHub Releases](https://github.com/TJZine/LineupDesktop/releases)
page and download only the assets attached to the selected release. Windows
releases are portable ZIPs and are unsigned. Android TV, Google TV and
Android-based Fire TV releases are APKs for Android 9+ ARM devices. If the
release page has no suitable asset, use a private build supplied by the
maintainer instead of an unofficial mirror.

For a Windows ZIP, optionally compare its digest with the attached `.sha256`
file and the release notes before extracting it:

```powershell
Get-FileHash -Algorithm SHA256 .\FILE.zip
```

Use **Extract All**, keep the package together, and run `lineup_desktop.exe`.
The package needs its adjacent DLLs, `data` directory, and a GPU driver or
Vulkan Runtime providing `vulkan-1.dll`. Windows may show “Windows protected
your PC” because the MVP package is unsigned. Choose **More info → Run anyway**
only for a ZIP downloaded from the official release page. [Smart App Control](https://learn.microsoft.com/en-us/windows/apps/develop/smart-app-control/overview)
blocks unknown unsigned code by default and provides no per-app exception. Run
Lineup Desktop as a standard user.

To update, extract the new ZIP into a new folder and then delete the old
application folder. Settings and lineups are kept in app data. To uninstall,
delete the application folder. Saved data remains until you separately remove
it, which permanently deletes settings and lineups.

On Android TV, Google TV or Android-based Fire TV, enable installation from
unknown sources for the installer app (such as Downloader or a file manager),
or use `adb install`. Update an existing installation with `adb install -r`
or the equivalent file-manager action. Uninstalling first deletes lineups and
sign-in. Media the device cannot decode natively, such as
DTS/TrueHD-only audio on many sticks, will not play in this version.

Developers can build the native development player on macOS or Windows.
Start with [Development](docs/DEVELOPMENT.md).

```sh
flutter pub get
dart tool/format.dart --check
flutter analyze
TZ=America/New_York flutter test # canonical full suite on macOS/Linux
```

Windows contributors should run the focused Windows commands in
[Development](docs/DEVELOPMENT.md); canonical golden verification runs on
macOS with the timezone above.

Windows playback additionally requires the pinned LGPL libmpv runtime and the
repository-owned Flutter DirectComposition engine patch. Do not substitute
unpinned components; follow the exact Windows procedure in
[Development](docs/DEVELOPMENT.md).

## Documentation

| Document | Purpose |
| --- | --- |
| [Documentation index](docs/README.md) | Audience-oriented map of the project documentation |
| [User Guide](docs/user-guide.md) | Setup, navigation, controls, settings, privacy, and troubleshooting |
| [Contributing](CONTRIBUTING.md) | Contribution workflow, architecture constraints, and review expectations |
| [Development](docs/DEVELOPMENT.md) | Toolchain, commands, native build setup, and engineering practices |
| [Architecture](docs/architecture.md) | Component ownership, implemented state, and dependency decisions |
| [Windows Native Acceptance](docs/windows-native-validation.md) | Physical-machine test campaign and Codex handoff |
| [Release security](docs/release-security.md) | Maintainer release, artifact and publication checks |
| [Release acceptance](docs/release-acceptance.md) | One-pass Android TV, Fire TV and Windows acceptance |
| [Windows Runtime Provenance](docs/windows-runtime.md) | libmpv/FFmpeg/libplacebo provenance and redistribution obligations |
| [Open obligations and historical evidence](docs/open-obligations.md) | Pending product/platform work and recoverable campaign evidence |
| [Product Parity — August 23, 2026 audit](docs/product-parity.md) | Dated audit with explicitly dated updates |
| [Desktop UI target specification](docs/desktop-ui-design-spec.md) | Approved Guide/PiP composition target; implementation and physical acceptance remain separate evidence |
| [Security Policy](SECURITY.md) | Private vulnerability reporting and secret-handling rules |

## Security and privacy

Plex credentials are kept outside ordinary application state and durable JSON.
Diagnostics are bounded and redact credentials, authorization headers,
token-bearing URLs, and private paths at their owner. Even so, review every log
or screenshot before sharing it.

Report security issues privately using [SECURITY.md](SECURITY.md). Do not post
Plex tokens, authentication headers, tokenized URLs, private media metadata, or
unredacted diagnostics in issues or pull requests.

## Project status

The Flutter-native replatform is the active implementation. The historical
Electron/TypeScript/C# source is preserved on `electron-ui` at the immutable
`bfaee636748f2a0d442f3690b7ba5262d32ff17c` baseline. `initial-build` is a
later Flutter-replatform milestone; neither branch is a compatibility target.

The [single unfinished-work register](docs/open-obligations.md) separates known
repairs, verification gaps, investigations, new features and release engineering.
It includes Windows patched-engine/lifecycle/package acceptance, macOS signed
distribution and older-OS compatibility, and explicitly deferred human checks.
The [Opus 5.5 handoff](docs/handoffs/opus-5-5-core-readiness-handoff.md) describes
core stabilization and bounded TV-platform feasibility work.

## License

Lineup Desktop source is available under the
[Apache License 2.0](LICENSE). Bundled native components retain their own
licenses and redistribution requirements; see
[Windows Runtime Provenance](docs/windows-runtime.md).
