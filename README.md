<p align="center">
  <img src="assets/branding/lineup-wordmark.png" alt="Lineup Desktop" width="420">
</p>

<p align="center">
  <strong>A native desktop client for building and watching Plex-powered virtual TV channels.</strong>
</p>

<p align="center">
  <a href="https://github.com/TJZine/LineupDesktop/actions/workflows/ci.yml?query=branch%3Areplatform%2Fflutter-native">
    <img src="https://github.com/TJZine/LineupDesktop/actions/workflows/ci.yml/badge.svg?branch=replatform%2Fflutter-native" alt="CI status">
  </a>
  <a href="LICENSE">
    <img src="https://img.shields.io/badge/license-Apache--2.0-blue.svg" alt="Apache 2.0 license">
  </a>
  <img src="https://img.shields.io/badge/status-pre--release-orange.svg" alt="Pre-release status">
</p>

> [!IMPORTANT]
> Lineup Desktop is under active development. There is no supported public
> installer or release yet. Windows native playback is implemented, but final
> physical-device, media-compatibility, HDR, packaging, and release acceptance
> are still in progress.

Lineup Desktop turns a Plex library into a deterministic, television-style
lineup. It combines channel creation, a responsive electronic program guide,
and native desktop playback while keeping product behavior in Flutter/Dart and
the Windows media boundary deliberately narrow.

## Highlights

- Plex PIN sign-in, Plex Home profiles, server discovery, and secure credential
  storage
- A guided Channel Builder with library, playlist, collection, genre, decade,
  studio, actor, and director strategies
- Custom channels built from an entire library or hand-picked media
- Classic picture-in-picture and full-video Overlay Guide layouts
- Native Windows playback with an OSD, mini Guide, channel entry, seeking,
  track selection, sleep timer, and fullscreen controls
- Five themes, compact and comfortable Guide densities, reduced motion, and
  larger focus indicators
- Bounded, credential-safe diagnostics intended for support and testing

## Platform status

| Platform | Current status |
| --- | --- |
| Windows 10/11 x64 | Primary target. Flutter UI, libmpv playback, native video presentation, and portable packaging are implemented. Final real-hardware and release acceptance remains pending. |
| macOS 12 or newer | Portable Flutter UI, onboarding, channel management, Guide, settings, and secure-storage development flows build successfully. Playback is intentionally reported as unsupported. |
| Linux | Not currently targeted. |

See [Architecture](docs/architecture.md) for the ownership model and
[Windows Native Acceptance](docs/windows-native-validation.md) for the evidence
still required before broader release claims.

## First run

A private test build guides the user through:

1. Link a Plex account with a QR code or four-character PIN.
2. Choose a Plex Home profile, including protected-profile PIN entry.
3. Select a reachable Plex Media Server.
4. Confirm the system-selected audio-output behavior.
5. Select libraries and build or review the initial channel lineup.

The main application then provides **Guide**, **Channels**, **Settings**,
**Diagnostics**, and **Player** destinations. The
[User Guide](docs/user-guide.md) documents the complete flow, controls,
settings, privacy behavior, and troubleshooting steps.

## Getting a build

No public release artifacts are published yet. Private testers should use only a
build supplied by the maintainer and should verify its source commit and package
hash before running it. Do not copy only the executable out of the portable
package; the adjacent runtime files and `data` directory are required.

Developers can build the portable Flutter application on macOS or the complete
native player on Windows. Start with [Development](docs/DEVELOPMENT.md).

```sh
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

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
| [Windows Runtime Provenance](docs/windows-runtime.md) | libmpv/FFmpeg/libplacebo provenance and redistribution obligations |
| [Portable UI Parity](docs/ui-parity.md) | Detailed source, test, and visual-parity evidence record |
| [Guide PiP Specification](docs/guide-pip-composition-spec.md) | Approved Guide/PiP composition and physical-acceptance requirements |
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
Electron/TypeScript/C# code remains on `initial-build` as reference material,
not as a compatibility target.

The principal remaining release work is physical Windows acceptance of native
video composition, replacement playback, hardware decode, HDR behavior,
fullscreen and high-DPI transitions, input/focus behavior, and the final
portable package on clean test systems.

## License

Lineup Desktop source is available under the
[Apache License 2.0](LICENSE). Bundled native components retain their own
licenses and redistribution requirements; see
[Windows Runtime Provenance](docs/windows-runtime.md).
