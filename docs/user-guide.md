# Lineup Desktop User Guide

**Status:** Pre-release guidance for private Windows testers and portable
Flutter UI evaluation.

Lineup Desktop builds scheduled virtual television channels from a Plex library
and presents them through a desktop Guide and Player. This guide describes the
current Flutter-native application. It does not apply to the historical
Electron implementation preserved on `electron-ui`.

## Before you start

| Requirement | Current expectation |
| --- | --- |
| Operating system | Windows 10 or Windows 11, x64, for native playback and packaged testing |
| Graphics runtime | A current GPU driver or Vulkan Runtime that provides `vulkan-1.dll` |
| Plex | A Plex account and a reachable Plex Media Server with accessible movie or TV libraries |
| Build | A complete private portable package supplied by the maintainer; no public release is available yet |
| Network | Access to Plex authentication and to the selected Plex server, directly or through an available remote/relay connection |

macOS 12 or newer can run the portable Flutter application for UI and workflow
development, but media playback is intentionally reported as unsupported.

## Install a private Windows build

1. Obtain the package and its SHA-256 hash directly from the maintainer.
2. Verify the archive hash before extracting it.
3. Extract the entire archive to a normal user-writable directory.
4. Read `SYSTEM-REQUIREMENTS.txt` and `BUILD-INFO.txt` in the package.
5. Launch `lineup_desktop.exe`.

Do not move only `lineup_desktop.exe`; the adjacent DLLs and `data` directory
are part of the application. Do not run Lineup Desktop as Administrator.

A private pre-release build may be unsigned. Proceed past an operating-system
warning only when the package came through the expected private testing channel
and its hash matches the maintainer-provided value.

## First-run setup

### 1. Link Plex

Select **Sign in to Plex**. Scan the displayed QR code or visit `plex.tv/link`
on another device and enter the four-character code. The screen shows the
remaining expiration time.

When a code expires or a request fails, select **Request a new code**. Cancelling
sign-in removes the pending credential state before returning to the welcome
screen.

### 2. Choose a Plex Home profile

Select the person who is watching. Protected profiles open a four-digit PIN
keypad and also accept number-row or numpad input.

The profile determines the secure credential scope, selected server, saved
lineup, and related persisted state. Switching profiles does not intentionally
reuse another profile's server or lineup.

### 3. Select a Plex Media Server

Choose a discovered server. Lineup prioritizes usable direct connections before
relay connections and records only the selected connection type and measured
probe latency.

When no server appears:

- confirm Plex Media Server is running and reachable;
- select **Retry discovery**;
- switch profiles when the expected server belongs to another profile; or
- clear the saved server when a previous selection is no longer valid.

### 4. Confirm audio behavior

The current Desktop audio step confirms that Lineup uses the
system-selected output. Device selection and passthrough controls remain hidden
until the native player can report and consume them accurately.

### 5. Build the initial lineup

Channel Setup has three stages:

1. Select the movie and TV libraries Lineup may use.
2. Configure channel strategies, ordering, build mode, and limits.
3. Review the proposed changes before applying them.

Available strategy families include Plex playlists, collections, recently added
content, genres, decades, studios, actors, and directors. Depending on the
strategy, channels can be generated per library or across selected libraries.

The review step applies the accepted plan atomically. Cancelling or a failed
save preserves the previous lineup.

## Main destinations

| Destination | Purpose |
| --- | --- |
| Guide | Browse the schedule, inspect focused programs, filter by library, jump to now, tune current programs, and open the Player |
| Channels | Re-run Channel Builder or create, edit, and delete custom channels |
| Settings | Configure themes, Guide behavior, accessibility, Plex profile/server selection, and diagnostics |
| Diagnostics | Review bounded, credential-safe support events from the current session |
| Player | Watch the tuned channel and use playback, track, channel, sleep, and fullscreen controls |

**Windows playback acceptance:** Player, Classic PiP, and Overlay describe the
intended private-test behavior. Native video composition and live Plex playback
have not yet passed the current branch's physical Windows acceptance.

Guide and Player use an immersive layout. Open the **Lineup** menu from either
surface to reach the other destinations. Management screens use the persistent
navigation rail.

## Guide

Lineup distinguishes four identities that may be visible at the same time:

- **Focused**: the program currently being inspected with the keyboard, remote,
  or pointer.
- **Selected**: the explicit program selection.
- **Tuned**: the channel currently playing.
- **Airing**: the program whose schedule includes the current time.

Moving focus does not retune playback. Activating a currently airing program
tunes its channel and closes the Guide to the Player.

The default **Classic with PiP** layout keeps the schedule primary and displays
the active video in a responsive picture-in-picture area. The optional
**Overlay** layout keeps the Guide over full video. Both layouts retain a
single Player and playback session.

Use the library selector in the Guide toolbar when **Library filters** are
enabled. **Jump to now** returns the time window and focus to the current
schedule.

The default Guide uses a detailed two-hour window and comfortable rows so its
visual scale stays close to the webOS Guide. A three-hour **Wide** option and
the preserved 4, 6, 8, and 12-hour desktop ranges are available when more of
the schedule matters than cell detail. Compact rows remain available as a
desktop override.

Focused program cells reveal long titles with a slow ticker; unfocused cells
remain stable and ellipsized. Reduce Motion disables the ticker. The program
information area can use artwork-derived color bleed, the current theme, or a
Plex backdrop, and can prefer Plex clear title logos when available. Missing
logos and artwork fall back to text and themed surfaces.

## Player

Move the pointer or click/tap the Player to show the on-screen controls. The OSD
provides:

- current channel and program information;
- playback position and seeking;
- previous channel, play/pause, and next channel;
- available audio and subtitle tracks;
- sleep timer state;
- native quality/decoder/output facts when the Windows player reports them; and
- fullscreen entry and exit.

Unavailable tracks or unsupported native actions remain disabled rather than
showing controls that cannot work.

The mini Guide displays a bounded group of nearby channels without leaving
playback. Selecting a row replaces the current tune through the same Player
owner.

## Keyboard and remote controls

Media and remote keys depend on what the operating system and input device
report to Flutter.

| Context | Action | Keys |
| --- | --- | --- |
| Management screens | Move between controls | `Tab` / `Shift+Tab` |
| Management screens | Activate focused control | `Enter` or `Space` |
| Anywhere in the ready app | Open Guide / Player / Settings | `Ctrl+G` / `Ctrl+P` / `Ctrl+,` |
| Anywhere in the ready app | Open destination 1-5 | `Ctrl+1` Guide, `Ctrl+2` Channels, `Ctrl+3` Settings, `Ctrl+4` Diagnostics, `Ctrl+5` Player |
| Anywhere in the ready app | Open Settings directly | `F3` |
| Guide | Move between channels | `Up` / `Down` |
| Guide | Move between scheduled programs | `Left` / `Right` |
| Guide | Move by a visible page | `Page Up` / `Page Down` |
| Guide | Jump to the current time | `Home`, `P`, or Media Play |
| Guide | Select/tune a currently airing program and open Player | `Enter`, numpad `Enter`, `Space`, or Select |
| Guide | Close Guide to Player when playback exists; otherwise open the Lineup menu | `Esc`, `Backspace`, Back, `G`, or `F2` |
| Player | Open full Guide | `G` or `F2` |
| Player | Show mini Guide | `Up` |
| Player | Show or hide OSD | `Down` or `Enter` shows; `I` toggles |
| Player | Seek backward/forward | `Left` or `J` = 10 seconds back; `Right` or `L` = 30 seconds forward |
| Player | Play or pause | `Space`, `K`, or Media Play/Pause |
| Player | Previous/next channel | `Page Up` / `Page Down` |
| Player | Enter a channel number | Number keys; confirm with `Enter` while the entry overlay is open |
| Player | Audio / subtitle tracks | `A` / `C` |
| Player | Sleep timer | `S` |
| Player | Toggle fullscreen | `F` or `F11` |
| Player | Close the active overlay; otherwise return to Guide | `Esc`, `Backspace`, or Back |
| Mini Guide | Browse nearby channels | `Up` / `Down` |
| Mini Guide | Move seven channels | `Page Up` / `Page Down` |
| Mini Guide | Tune focused channel | `Enter`, `Space`, or Select |
| Mini Guide | Open full Guide | `Right` |
| Mini Guide | Close | `Esc`, `Backspace`, or Back |

Dedicated Media Play, Pause, Stop, Rewind, and Fast Forward keys are also
handled when available. Core playback keys continue to work while the OSD is
visible, and the OSD follows the configured auto-hide duration.

## Channels

### Channel Builder

Use **Channel builder** for a generated lineup. The builder can replace, append
to, or merge with the current lineup after review. Limits are bounded, and the
accepted plan is written as one lineup change.

### Custom channels

Select **Create channel** or edit an existing channel. A custom channel
supports:

- a unique channel number from 1 through 1000;
- an entire selected library or hand-picked media;
- sequential, shuffle, or block playback;
- optional inclusion of watched items for library-backed channels; and
- retention of previously selected hand-picked items that are temporarily
  unavailable, until explicitly removed.

Deletion requires confirmation and cannot be undone.

## Settings

| Category | Current controls |
| --- | --- |
| Appearance | Ember & Steel, Slate & Pine, Swiss Minimal, DirecTV Classic, and Glassmorphism themes |
| Guide | Classic with PiP or Overlay presentation; detailed 2-hour, wide 3-hour, or desktop-extended 4/6/8/12-hour windows; 0-180 minute past window; comfortable or compact rows; color-bleed/theme/artwork information backgrounds; clear-logo preference; library filters; Now Playing context; 2-15 second OSD auto-hide |
| Accessibility | Reduce motion and larger keyboard/controller focus indicators |
| Account | Switch Plex Home profile, switch or clear Plex server selection, and optionally show the profile picker at startup |
| Support | Enable or disable bounded redacted diagnostic recording |

Settings save immediately. When persistence fails, the previous value remains
active and the screen shows an error.

## Diagnostics and safe support reports

Diagnostics are disabled by default. Enable **Record redacted diagnostics** in
**Settings > Support** before reproducing a problem that needs support context.

The application excludes credentials, authorization headers, token-bearing
URLs, and private paths from diagnostic entries. Redaction lowers risk but does
not replace review. Before sharing anything:

1. Inspect every line and screenshot.
2. Remove private media titles or account details that are not needed.
3. Never include a Plex token, authentication header, tokenized URL, or
   credential-store content.
4. Include the source commit or package `BUILD-INFO.txt`, Windows version, GPU
   and driver, display resolution/scaling, connection type, and exact
   reproduction steps.

Use the repository bug-report template for ordinary issues. Report
vulnerabilities only through the private process in
[SECURITY.md](../SECURITY.md).

## Troubleshooting

| Symptom | Action |
| --- | --- |
| Plex link code expired | Select **Request a new code** and complete linking before the new timer expires. |
| No Plex servers found | Confirm the server is online and reachable, retry discovery, switch profile, or clear a stale saved server. |
| The app reports playback unsupported on macOS | This is expected. macOS currently supports portable UI development, not native playback. |
| Windows reports that `vulkan-1.dll` is missing | Install or update the GPU vendor's current driver or an appropriate Vulkan Runtime. Do not copy a driver DLL from another machine into the package. |
| Audio plays but video is black or hidden | Record the exact window size, display scaling, fullscreen state, Guide layout, whether audio continues, and whether the problem follows a resize/minimize/restore transition. Treat this as a native-composition failure and report it with the current commit. |
| A replacement channel leaves stale audio/video | Stop testing that scenario, record both channel transitions and timestamps, and report it as a native playback-lifetime failure. |
| A setting or lineup change fails | The previous state should remain. Retry after confirming the Plex server and local storage are available. |
| A private portable package does not launch | Verify the complete package was extracted, `SYSTEM-REQUIREMENTS.txt` is satisfied, the archive hash matches, and the GPU driver supplies `vulkan-1.dll`. |

## Known limitations

- There is no supported public installer, updater, or release channel.
- Windows native playback and packaging have not yet completed the full
  physical acceptance matrix on the current branch.
- macOS playback is intentionally unsupported.
- Audio-output selection and passthrough controls are not exposed.
- Broad codec/container, HDR, multi-monitor, high-DPI, gamepad, signing, and
  clean-system package coverage remain release-gate work.
- Pre-release behavior and persisted state may change before the first public
  version.
