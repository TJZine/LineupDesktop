---
title: Platform support
description: See Lineup's current platform support and testing status.
---
# Platform support

See which systems Lineup targets and what still needs testing.
{ .lead }

| Platform | Current support |
| --- | --- |
| Windows 10 and 11, x64 | Primary desktop target. The pre-release package is an unsigned portable ZIP. Use a current GPU driver or Vulkan Runtime that provides `vulkan-1.dll`. See [Windows installation](../getting-started/windows.md). |
| macOS, Apple Silicon | Development and private testing with libmpv playback, Guide picture-in-picture, HDR presentation, and Mac integration. The supported minimum is macOS 14 Sonoma. See [macOS](../getting-started/macos.md). |
| Android TV, Google TV, and Android-based Fire TV | Sideloaded APK for Android 9 or later on ARM (`armeabi-v7a` and `arm64-v8a`), with Media3 playback and D-pad controls. Vega OS devices cannot install Android APKs. See [Android TV and Fire TV](../getting-started/android-tv.md). |
| Apple TV | Feasibility research only. There is no tvOS implementation. |
| Linux | Lineup does not currently target Linux. |

See [Architecture](https://github.com/TJZine/LineupDesktop/blob/main/docs/architecture.md) for the playback platform boundaries.

## Testing status

### Windows

Windows playback and packaging still need the full physical test matrix on the exact release candidate. The current Guide uses picture-in-picture. Video layering, DPI and fullscreen behavior, keyboard and screen-reader support, and clean-system package and device coverage still need physical testing. Automated checks cover timed overlays, focus, and sequential parts. Windows end-of-file and schedule-continuation boundaries still need physical testing.

Integrated fullscreen HDR, including content and display transitions, remains unverified on physical hardware. Both Windows matching routes are enabled according to detected capabilities. Windows 11 matching remains unverified on physical hardware. The format and device claims remain provisional. Deeper coverage includes codecs, HDR, TrueHD and DTS decoded to PCM, text and image subtitles, multiple monitors, and high-DPI setups. Gamepad testing and clean-system package coverage remain open.

See [Windows Native Acceptance](https://github.com/TJZine/LineupDesktop/blob/main/docs/windows-native-validation.md) for the required checks.

### Android TV and Fire TV

Direct Play and couch-use checks remain open. You can reach Channel Studio's manual editor and Air Check, but they have not passed remote-only testing for this beta. Upgrade testing requires a production-signed APK. See [Android runtime](https://github.com/TJZine/LineupDesktop/blob/main/docs/android-runtime.md).

### macOS

The preserved beta candidate still builds with a macOS 12 deployment target. Runtime coverage is recorded on macOS 27. Sonoma hardware validation, distribution and remaining runtime checks are open, including signed distribution.
