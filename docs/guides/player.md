---
title: The Player
description: Watch the tuned channel with Lineup's playback controls.
---
# The Player

Watch the tuned channel and open its controls without leaving the picture.
{ .lead }

On Windows, Lineup runs in a single window. Opening it again brings that window to the front.

??? note "Details"
    Opening another copy ignores its launch arguments, including a local media file passed to it.

## On-screen controls

Move the pointer or click or tap the picture to show the on-screen controls. You can also press ++enter++ or, on TV, Select while the controls are hidden. The channel number appears in the upper right. The program title is on the lower left, secondary actions are on the lower right, and the progress line runs along the bottom. Above the line, you see the current and total time and time left when the duration is known. When the next program is known, **Up next** shows its scheduled start and title.

With **Use title artwork** enabled, Lineup shows Plex title artwork when it can load and fit it. Otherwise it shows the title in text. The Player uses the duration reported during playback when available and the schedule duration otherwise.

The controls hide after the time you choose in [Settings](settings.md). They stay open while keyboard focus is inside them, and the full timeout restarts when focus leaves. On TV, action keys reset the timeout and focus returns to the video when the controls hide. **Reduce motion** removes the Player overlay transition.

Open [Audio, subtitles and sleep](tracks-and-sleep.md) for track and timer controls. Unavailable playback actions stay disabled. See [Keyboard and remote](../reference/controls.md) for channel numbers, surfing, menu, and fullscreen shortcuts.

### DVR controls

**DVR playback controls** is off by default. The playback buttons are hidden, and Player shortcuts for play, pause, seek, stop, rewind, and fast forward are disabled. Channel surfing, number entry, Guide and Mini Guide tuning, tracks, sleep, menu, and fullscreen remain available.

Turn **DVR playback controls** on under **Settings** → **Playback** for previous and next channel buttons, play and pause, and seeking. See [Keyboard and remote](../reference/controls.md) for supported keys. For playback through multiple media parts, see [How schedules work](schedules.md#program-endings).

## Now Playing

On a keyboard, press ++i++ or ++arrow-down++ to expand the controls when a program is available. On TV, press Info if your remote has it, or press Down from the compact controls’ action row. Now Playing stays open when the pointer moves. It shares the usual actions, timing, progress, and **Up next**. It shows the loaded program's title or Plex title artwork, episode, runtime, year, genres, poster, and up to three lines of synopsis when available. Format information can include rating, resolution, HDR, a video codec such as HEVC or H.264, the audio codec, and the audio channel count.

When Plex supplies cast details, up to four portraits appear with names and roles. Assistive technology can read the full cast details. Missing or failed portraits use a person silhouette. With no cast details, the layout leaves the space available for the rest of the panel.

Press ++i++, ++enter++, ++escape++, Back, or **Close** to return to the compact controls. Use [Audio, subtitles and sleep](tracks-and-sleep.md) to go directly to a track list.

## Mini Guide

On a keyboard, press ++arrow-up++ from the video or compact controls. On TV, press Up with the controls hidden. The Mini Guide shows nearby channels over the picture. It stays open while you browse. Select a channel to tune it, open the full Guide, or close it when you're done.

## Fullscreen HDR on Windows

**Match display HDR in fullscreen** is on by default in **Settings** → **Playback**. Matching starts when you enter fullscreen playback in Player with the full Guide closed. Opening the Guide afterward keeps matching active. Lineup switches Windows HDR on for HDR programs and off for SDR programs, including when HDR was already on before fullscreen.

Leaving fullscreen, turning the setting off, stopping playback, an error, signing out, or closing Lineup releases the display and restores its original setting. A manual HDR change suspends matching and Lineup respects your choice. Moving to another display releases the old display and checks the new one.

??? note "Details"
    Eligible starts can show **Preparing playback**, then **Starting playback…** after two seconds. Playback waits for a display switch and 1.5 seconds to settle. It starts sooner when a switch is unnecessary or cannot proceed. A switch request can hold playback for up to four seconds. If video information remains unknown, Lineup eventually proceeds. Play releases the hold immediately, and Pause cancels automatic resume if DVR controls are on. Holds also work with DVR controls off and count toward delays between programs.

    Decoded PQ and HLG use HDR. Dolby Vision displays as HDR10, using the HDR10 base layer for profile 7. HDR10+ displays as static HDR10. Lineup chooses a Windows 10 or Windows 11 matching route based on detected capabilities. See [Platform support](../reference/platforms.md#testing-status) for what still needs physical testing.

    A separate recovery process attempts to restore the original display setting if Lineup exits unexpectedly. Lineup changes display state only after confirming that process is ready. Power loss, an operating system crash, an interrupted shutdown, or ending both processes can leave the display in its last state.
