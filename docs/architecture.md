# Architecture

Lineup Desktop is a native Flutter/Dart application. The historical Electron
implementation is preserved at `origin/initial-build`; the rewrite baseline is
`bfaee636748f2a0d442f3690b7ba5262d32ff17c`. It is reference material, not a
runtime, source-compatibility, or migration target.

```text
Flutter/Dart application
    |
    +-- Plex, channels, scheduling, settings, persistence, diagnostics
    |
    +-- Flutter Guide, OSD, navigation, focus, input, accessibility
    |
    +-- narrow native player boundary
              |
              +-- C++ / libmpv
              +-- Windows native video presentation
              +-- DirectComposition integration
```

## Accepted ownership

The Dart application is a feature-oriented modular monolith with one bootstrap
composition root. Product policy remains in Dart: Plex coordination, channels,
deterministic schedules, settings, persistence, diagnostics, playback
coordination, and every visible or accessible interaction. Dependencies are
explicit constructor arguments. Feature state remains local until a real
cross-feature asynchronous state graph justifies one mature state-management
dependency.

C++ is reserved for behavior that materially needs native ownership: libmpv
lifetime and commands, decoded-frame presentation, Windows platform objects,
DirectComposition, and native media telemetry. Native handles, mpv internals,
and token-bearing URLs do not enter ordinary Flutter UI state.

The `NativePlayer` Dart interface exists because native platform code and test
doubles are a genuine seam. Its initial contract covers lifecycle, media
replacement, transport, seeking, status, and events. Track, volume, quality,
and presentation controls will be added only with their first real workflow so
the Windows implementation is not forced to support speculative protocol.

## Implemented now

- Root Flutter project targeting only macOS and Windows.
- Application bootstrap, theme tokens, keyboard-focus-aware Material controls,
  semantic labels, navigation shell, and explicit startup failure surface.
- Feature entry points for Guide, Channels, Settings, and Diagnostics without
  fake product data.
- The Dart native-player seam and an explicit macOS unsupported development
  backend. It never reports successful playback.
- Flutter format, analysis, tests, and macOS/Windows scaffold builds in CI.

## Not implemented yet

Plex access, secure persistence, channels, scheduling, full Guide/OSD screens,
diagnostics, and production media playback are not yet implemented. In
particular, there is no C++ or libmpv code in this foundation. The next native
media work is the Windows player implementation and requires Windows evidence
for libmpv behavior, hardware decode, HDR, native video composition, and
DirectComposition integration.

## Dependency decision

The runtime depends only on Flutter. Flutter built-ins are sufficient for this
shell and are easier to debug than introducing a state framework before there
is shared asynchronous state. `flutter_lints` and `flutter_test` are development
dependencies under their SDK/BSD licenses. Re-evaluate packages when a concrete
feature can show a material reliability or ownership advantage.
