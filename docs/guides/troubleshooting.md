---
title: Troubleshooting
description: Find steps for common Lineup problems.
---
# Troubleshooting

Find the next step when Lineup can't connect, play, install, or save a change.
{ .lead }

## Plex linking and servers

| What you see | What to do |
| --- | --- |
| The Plex code expires, or Plex rejects or cannot complete the link | Choose **Request a new code** and complete linking before the new timer expires. |
| Lineup can't confirm secure credential storage | Choose **Retry secure cancellation** before starting another attempt. See [Privacy and stored data](../reference/privacy.md#plex-sign-in-and-servers) for how cancellation handles your sign-in. |
| **No servers found** | Follow the [server discovery steps](profiles-and-servers.md#plex-media-server), or [sign out](profiles-and-servers.md#sign-out) to link Plex again. |

## Installation and playback

| What you see | What to do |
| --- | --- |
| A portable Mac build reports playback is unsupported | Follow the [macOS runtime build instructions](https://github.com/TJZine/LineupDesktop/blob/main/docs/macos-runtime.md) to test playback. |
| Windows can't find `vulkan-1.dll` | Install or update your GPU vendor's driver or an appropriate Vulkan Runtime. Keep DLLs from other PCs out of the package. |
| Smart App Control blocks Lineup | See the [Windows installation warning](../getting-started/windows.md#install). |
| Audio plays but the video is black or hidden, or the previous channel keeps playing | See [Support reports](support-reports.md#share-safely) for what to record and how to report it. |
| Android says the APK cannot be installed | Check your device and unknown-source settings under [Android installation](../getting-started/android-tv.md#install). To replace the current APK, use the [update steps](../getting-started/android-tv.md#update). |
| Android cannot play a format | Check [Known limitations](../reference/limitations.md) and choose media your device can play. |

??? note "For testers"
    If a private portable package does not launch, check the complete package was extracted, the archive hash matches, `SYSTEM-REQUIREMENTS.txt` is satisfied, and the GPU driver provides `vulkan-1.dll`.

## Saved data and changes

If a setting or lineup change fails, the previous state should remain. Check that your Plex server and local storage are available, then try again.

If Lineup reports corrupt saved data, it moves the unreadable data to a separate file and starts with an empty setup. Review the setup before dismissing the banner.

??? note "Details"
    This applies to saved data with invalid text encoding, malformed JSON, or an invalid structure. Other storage read failures stop startup and preserve your data.
