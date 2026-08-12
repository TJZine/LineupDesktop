# Lineup Desktop

A pre-MVP native desktop application for building and watching Plex-powered
virtual TV channels. The application is being rewritten in Flutter/Dart with a
future C++/libmpv Windows video backend.

The current branch provides the macOS/Windows Flutter foundation and a runnable
macOS development shell. Product features and production playback are not yet
implemented.

## Get started

Install the pinned Flutter SDK described in
[`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md), then run:

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d macos
```

See [`docs/architecture.md`](docs/architecture.md) for ownership and implemented
status. The complete historical implementation remains available on the
`initial-build` branch and in Git history.
