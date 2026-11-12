---
title: Known limitations
description: Review Lineup's known limitations.
---
# Known limitations

Review the limits of the pre-release app before relying on it for playback or updates.
{ .lead }

- Check [GitHub Releases](https://github.com/TJZine/LineupDesktop/releases) for builds available on your platform. Behavior and saved data can change before the first public release.
- On Android TV and Fire TV, Direct Play uses the device's own decoder. Media it cannot decode, such as DTS/TrueHD-only audio on many sticks, will not play. Choose a file the device can play.
- On Android, a paused seek can skip overlapping ASS/SSA dialogue in either styling mode. Changing style cannot restore events missed by the decoder. See the [Media3 seek limitation](https://github.com/TJZine/LineupDesktop/blob/main/docs/android-runtime.md#subtitle-presentation-and-device-captions).
- Audio-output selection and passthrough controls are unavailable. Lineup doesn't block any format itself; whether a file plays depends on your device. [Platform support](platforms.md#testing-status) lists the formats and configurations that still need testing.
- You cannot choose an alternate Plex media version. Lineup plays sequential parts of the version it selects. See [How schedules work](../guides/schedules.md#program-endings).
- If switching Plex Home profiles fails or you cancel it, Lineup may not always restore the previous profile's sign-in. Sign in again if that happens.
- See [Platform support](platforms.md#testing-status) for gamepad, TV remote, installation, and release testing status.
