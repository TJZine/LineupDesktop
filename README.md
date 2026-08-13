# Lineup Desktop

A pre-MVP native desktop application for building and watching Plex-powered
virtual TV channels. Lineup Desktop is being replatformed from the historical
Electron/TypeScript/C# implementation to Flutter/Dart with a narrow native
media boundary.

The current branch provides:

- a Flutter shell and shared application structure for Windows and macOS
- a Windows C++/libmpv playback owner behind a bounded platform-channel API
- native child-window video presentation beneath Flutter overlays
- an owned Flutter 3.47.0 DirectComposition engine patch and reproducible
  Windows development build path
- a shared Flutter player, OSD, mini Guide, full Guide, track menus, channel
  entry, sleep timer, fullscreen intent, and deterministic overlay ownership
- an explicit unsupported-playback state on macOS rather than a false success
- Plex PIN authentication, Home profiles, HTTPS server discovery, library and
  media loading, and secure credential ownership
- deterministic channels, custom-channel authoring, scheduling, stream policy,
  durable settings/state, and bounded redacted diagnostics
- upstream-shaped TV onboarding with QR/PIN linking, profile/server/audio
  setup, and a three-step Channel Builder supporting eight Plex source
  strategies, review, merge/append/replace, and lineups up to 1,000 channels
- a lazy Guide with stable logical focus, bounded schedule/artwork caches,
  library filters, configurable time/density, and keyboard/remote/mouse input

Remote Plex playback still requires Windows acceptance. Distributable libmpv
packaging and final Windows hardware/HDR acceptance are not yet implemented or
proven. Real Plex and macOS Keychain workflows still require manual
account-specific acceptance.

## Get started

Install the exact Flutter SDK described in
[`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md), then run:

```sh
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter run -d macos
```

The Windows player requires the pinned libmpv development asset and patched
Flutter engine documented in [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md).

See [`docs/architecture.md`](docs/architecture.md) for component ownership and
implemented status. The complete historical implementation remains available
on the `initial-build` branch and in Git history.
