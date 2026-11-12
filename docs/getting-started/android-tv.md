---
title: Android TV and Fire TV
description: Install Lineup on Android TV, Google TV, or Fire TV.
---
# Android TV and Fire TV

Sideload the Lineup APK on Android TV, Google TV, or Android-based Fire TV.
{ .lead }

## Install

Use a device running Android 9 or later on ARM. Fire TV devices running Vega OS cannot install Android APKs.

1. Get the APK from [GitHub Releases](https://github.com/TJZine/LineupDesktop/releases) when a public build is available.
2. On your TV, allow installation from unknown sources for the app you use to open the APK, such as Downloader or a file manager.
3. Open the APK. You can also install it from a computer with `adb install <apk>`.

## Update

Open the new APK over the Lineup app you already have. Don't uninstall the old app first. See [Privacy and stored data](../reference/privacy.md#update-or-remove-lineup) for what uninstalling removes.

??? note "For testers"
    To update an installed production build from a computer, run `adb install -r <apk>`.

See [Known limitations](../reference/limitations.md) for device playback limits and [Android runtime](https://github.com/TJZine/LineupDesktop/blob/main/docs/android-runtime.md) for platform details.
